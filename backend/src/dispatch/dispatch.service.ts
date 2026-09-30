import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DispatchStatus, OrderStatus, ProviderStatus } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { PushService } from '../notifications/push.service';
import { OrderEventsService } from '../notifications/order-events.service';
import {
  AdminAlertService,
  coarseArea,
} from '../notifications/admin-alert.service';
import { distanceKm } from '../common/geo';
import {
  DISPATCH_MAX_CANDIDATES,
  DISPATCH_MAX_RADIUS_KM,
  DISPATCH_OFFER_TIMEOUT_MS,
  DISPATCH_BATCH_SIZE,
  PROVIDER_HEARTBEAT_STALE_MS,
} from '../common/constants';
import { serializable } from '../common/transaction';
import { WalletService } from '../wallet/wallet.service';

const ACTIVE_ORDER_STATUSES: OrderStatus[] = [
  OrderStatus.MATCHED,
  OrderStatus.EN_ROUTE,
  OrderStatus.IN_PROGRESS,
];

/** นาทีของวันตามเวลาไทย (UTC+7) ใช้เช็กว่าช่างอยู่ในช่วงเวลาทำงานหรือยัง */
export function bangkokMinuteOfDay(now: Date = new Date()): number {
  const bangkok = new Date(now.getTime() + 7 * 60 * 60 * 1000);
  return bangkok.getUTCHours() * 60 + bangkok.getUTCMinutes();
}

export function isWithinWorkingHours(
  openMinute: number,
  closeMinute: number,
  minuteOfDay: number,
): boolean {
  // ช่วงเวลาข้ามเที่ยงคืน เช่น 20:00-06:00
  if (openMinute > closeMinute) {
    return minuteOfDay >= openMinute || minuteOfDay <= closeMinute;
  }
  return minuteOfDay >= openMinute && minuteOfDay <= closeMinute;
}

@Injectable()
export class DispatchService {
  private readonly logger = new Logger(DispatchService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly push: PushService,
    private readonly adminAlert: AdminAlertService,
    private readonly events: OrderEventsService,
    private readonly wallet: WalletService,
  ) {}

  /** เริ่มกระจายงาน: หาช่างที่เข้าเงื่อนไข เรียงตามระยะทาง แล้วเสนอให้คนใกล้สุดก่อน */
  async startDispatch(orderId: string): Promise<void> {
    const started = await this.prisma.order.updateMany({
      where: {
        id: orderId,
        status: OrderStatus.CREATED,
        OR: [
          { inspection: null },
          { inspection: { appointmentAt: null } },
          {
            inspection: {
              appointmentAt: { lte: new Date(Date.now() + 60 * 60_000) },
            },
          },
        ],
      },
      data: { status: OrderStatus.SEARCHING },
    });
    if (started.count !== 1) return;
    await this.offerToNextBatch(orderId);
  }

  /** เสนองานพร้อมกันให้กลุ่มช่างที่ใกล้ที่สุด คนแรกที่รับได้งาน */
  private async offerToNextBatch(
    orderId: string,
    { notifyNoMatch = true }: { notifyNoMatch?: boolean } = {},
  ): Promise<void> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: {
        dispatchAttempts: true,
        subService: { select: { name: true } },
      },
    });

    if (!order) return;
    if (
      order.status !== OrderStatus.SEARCHING &&
      order.status !== OrderStatus.CREATED
    ) {
      return;
    }

    const now = new Date();
    const hasActiveOffer = order.dispatchAttempts.some(
      (attempt) =>
        attempt.status === DispatchStatus.OFFERED && attempt.expiresAt > now,
    );
    if (hasActiveOffer) return;

    if (order.dispatchAttempts.length >= DISPATCH_MAX_CANDIDATES) {
      await this.markNoMatch(orderId, notifyNoMatch);
      return;
    }

    const alreadyOffered = new Set(
      order.dispatchAttempts.map((attempt) => attempt.providerId),
    );

    const candidates = await this.prisma.provider.findMany({
      where: {
        status: ProviderStatus.VERIFIED,
        isOnline: true,
        lastSeenAt: {
          gte: new Date(Date.now() - PROVIDER_HEARTBEAT_STALE_MS),
        },
        id: { notIn: [...alreadyOffered] },
        serviceCategories: { some: { categoryId: order.categoryId } },
        vehicleTypes: { some: { vehicleTypeId: order.vehicleTypeId } },
        orders: { none: { status: { in: ACTIVE_ORDER_STATUSES } } },
        dispatchAttempts: {
          none: {
            status: DispatchStatus.OFFERED,
            expiresAt: { gt: now },
          },
        },
      },
    });

    const minuteOfDay = bangkokMinuteOfDay();

    const ranked = candidates
      .filter((provider) =>
        isWithinWorkingHours(
          provider.openMinute,
          provider.closeMinute,
          minuteOfDay,
        ),
      )
      .map((provider) => ({
        provider,
        distance: distanceKm(
          order.pickupLat,
          order.pickupLng,
          provider.currentLat ?? provider.baseLat,
          provider.currentLng ?? provider.baseLng,
        ),
      }))
      .filter((entry) => entry.distance <= DISPATCH_MAX_RADIUS_KM)
      .sort((a, b) => a.distance - b.distance);

    const remainingSlots =
      DISPATCH_MAX_CANDIDATES - order.dispatchAttempts.length;
    const batch = ranked.slice(
      0,
      Math.min(DISPATCH_BATCH_SIZE, remainingSlots),
    );
    if (batch.length === 0) {
      await this.markNoMatch(orderId, notifyNoMatch);
      return;
    }

    const expiresAt = new Date(Date.now() + DISPATCH_OFFER_TIMEOUT_MS);
    await this.prisma.dispatchAttempt.createMany({
      data: batch.map((entry, index) => ({
        orderId,
        providerId: entry.provider.id,
        rank: order.dispatchAttempts.length + index + 1,
        distanceKm: entry.distance,
        status: DispatchStatus.OFFERED,
        expiresAt,
      })),
      skipDuplicates: true,
    });

    this.logger.log(`เสนองาน ${order.orderNo} ให้ช่าง ${batch.length} คน`);

    void this.push.offerToProviders(
      batch.map((entry) => ({
        id: entry.provider.id,
        distanceKm: entry.distance,
      })),
      {
        id: order.id,
        orderNo: order.orderNo,
        serviceName: order.subService.name,
      },
      Math.round(DISPATCH_OFFER_TIMEOUT_MS / 1000),
    );
  }

  private async markNoMatch(orderId: string, notify = true): Promise<void> {
    const updated = await this.prisma.order.updateMany({
      where: { id: orderId, status: OrderStatus.SEARCHING },
      data: { status: OrderStatus.NO_MATCH },
    });
    this.logger.warn(`ออเดอร์ ${orderId} ไม่มีช่างรับ ส่งต่อให้แอดมิน`);
    // แอดมินกดหาช่างใหม่เองแล้วยังไม่เจอ: แอดมินเห็นผลในหน้าจออยู่แล้ว ลูกค้าก็รู้แล้ว ไม่แจ้งซ้ำ
    if (updated.count === 0) return;
    this.events.emit(orderId, 'NO_MATCH');
    if (!notify) return;
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: {
        id: true,
        orderNo: true,
        customerId: true,
        pickupAddress: true,
        subService: { select: { name: true } },
      },
    });
    if (!order) return;
    void this.push.noMatch(order.customerId, order);
    void this.adminAlert.noMatch({
      orderNo: order.orderNo,
      serviceName: order.subService.name,
      area: coarseArea(order.pickupAddress),
    });
  }

  /**
   * แอดมินสั่งหาช่างใหม่ให้งานที่ไม่มีใครรับ (เช่น หลังโทรเรียกช่างให้เปิดแอป)
   * ล้างรอบเสนองานเดิมเพื่อให้ช่างที่เคยปฏิเสธ/หมดเวลาได้รับข้อเสนออีกครั้ง
   */
  async redispatch(orderId: string): Promise<void> {
    const reopened = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.order.updateMany({
        where: { id: orderId, status: OrderStatus.NO_MATCH },
        data: { status: OrderStatus.SEARCHING },
      });
      if (updated.count !== 1) return false;
      await tx.dispatchAttempt.deleteMany({ where: { orderId } });
      return true;
    });
    if (!reopened) {
      throw new BadRequestException('ส่งหาช่างใหม่ได้เฉพาะงานที่ไม่มีช่างรับ');
    }
    await this.offerToNextBatch(orderId, { notifyNoMatch: false });
  }

  /** ช่างกดรับงาน */
  async accept(orderId: string, providerId: string): Promise<void> {
    const attempt = await this.prisma.dispatchAttempt.findUnique({
      where: { orderId_providerId: { orderId, providerId } },
      include: { order: true },
    });

    if (!attempt || attempt.status !== DispatchStatus.OFFERED) {
      throw new BadRequestException(
        'งานนี้ไม่ได้ถูกเสนอให้คุณ หรือหมดเวลาแล้ว',
      );
    }
    if (attempt.expiresAt.getTime() < Date.now()) {
      throw new BadRequestException('หมดเวลากดรับงานแล้ว');
    }
    if (attempt.order.status !== OrderStatus.SEARCHING) {
      throw new BadRequestException('งานนี้ถูกรับไปแล้ว');
    }
    await serializable(this.prisma, async (tx) => {
      const provider = await tx.provider.findUnique({
        where: { id: providerId },
      });
      if (
        !provider ||
        provider.status !== ProviderStatus.VERIFIED ||
        provider.deletedAt ||
        !provider.isOnline
      ) {
        throw new BadRequestException(
          'บัญชีช่างต้องได้รับอนุมัติและเปิดรับงานอยู่',
        );
      }
      await this.wallet.assertCanTakeJobs(providerId, tx);
      const activeOrder = await tx.order.findFirst({
        where: { providerId, status: { in: ACTIVE_ORDER_STATUSES } },
        select: { id: true },
      });
      if (activeOrder) {
        throw new BadRequestException('คุณมีงานที่กำลังดำเนินการอยู่แล้ว');
      }

      const accepted = await tx.dispatchAttempt.updateMany({
        where: {
          id: attempt.id,
          status: DispatchStatus.OFFERED,
          expiresAt: { gt: new Date() },
        },
        data: { status: DispatchStatus.ACCEPTED, respondedAt: new Date() },
      });
      if (accepted.count !== 1) {
        throw new BadRequestException('งานนี้หมดเวลาหรือถูกรับไปแล้ว');
      }

      const claimed = await tx.order.updateMany({
        where: {
          id: orderId,
          status: OrderStatus.SEARCHING,
          providerId: null,
        },
        data: {
          providerId,
          status: OrderStatus.MATCHED,
          matchedAt: new Date(),
        },
      });
      if (claimed.count !== 1) {
        throw new BadRequestException('งานนี้ถูกรับไปแล้ว');
      }

      // ปิดข้อเสนอที่ค้างอยู่ของช่างคนอื่น ไม่ให้เห็นงานที่ถูกรับไปแล้ว
      await tx.dispatchAttempt.updateMany({
        where: {
          orderId,
          status: DispatchStatus.OFFERED,
          id: { not: attempt.id },
        },
        data: { status: DispatchStatus.EXPIRED },
      });
    });

    const provider = await this.prisma.provider.findUnique({
      where: { id: providerId },
      select: { nickname: true },
    });
    void this.push.matched(
      attempt.order.customerId,
      attempt.order,
      provider?.nickname ? `ช่าง${provider.nickname}` : 'ช่าง',
    );
  }

  /** ช่างกดปฏิเสธ — ส่งต่อคนถัดไปทันทีไม่ต้องรอหมดเวลา */
  async reject(orderId: string, providerId: string): Promise<void> {
    const attempt = await this.prisma.dispatchAttempt.findUnique({
      where: { orderId_providerId: { orderId, providerId } },
    });

    if (!attempt || attempt.status !== DispatchStatus.OFFERED) {
      throw new BadRequestException('งานนี้ไม่ได้ถูกเสนอให้คุณ');
    }

    const changed = await this.prisma.dispatchAttempt.updateMany({
      where: { id: attempt.id, status: DispatchStatus.OFFERED },
      data: { status: DispatchStatus.REJECTED, respondedAt: new Date() },
    });
    if (changed.count !== 1)
      throw new BadRequestException('ข้อเสนอนี้เปลี่ยนสถานะแล้ว');

    const otherActiveOffers = await this.prisma.dispatchAttempt.count({
      where: {
        orderId,
        status: DispatchStatus.OFFERED,
        expiresAt: { gt: new Date() },
      },
    });
    if (otherActiveOffers === 0) await this.offerToNextBatch(orderId);
  }

  /** งานที่ถูกเสนอให้ช่างคนนี้และยังไม่หมดเวลา */
  async listOffersForProvider(providerId: string) {
    return this.prisma.dispatchAttempt.findMany({
      where: {
        providerId,
        status: DispatchStatus.OFFERED,
        expiresAt: { gt: new Date() },
        order: { status: OrderStatus.SEARCHING },
      },
      include: {
        order: {
          include: {
            category: true,
            subService: true,
            vehicleType: true,
            photos: true,
            inspection: { select: { appointmentAt: true } },
          },
        },
      },
      orderBy: { offeredAt: 'desc' },
    });
  }

  /** ตรวจข้อเสนอที่หมดเวลาทุก 30 วินาที แล้วส่งงานต่อให้ช่างคนถัดไป */
  @Cron(CronExpression.EVERY_30_SECONDS)
  async expireStaleOffers(): Promise<void> {
    const due = await this.prisma.order.findMany({
      where: {
        status: OrderStatus.CREATED,
        OR: [
          { inspection: null },
          { inspection: { appointmentAt: null } },
          {
            inspection: {
              appointmentAt: { lte: new Date(Date.now() + 60 * 60_000) },
            },
          },
        ],
      },
      select: { id: true },
      take: 100,
      orderBy: { createdAt: 'asc' },
    });
    for (const order of due) {
      await this.startDispatch(order.id).catch((error) =>
        this.logger.error(`เริ่มหาช่างไม่สำเร็จ ${order.id}`, error),
      );
    }
    const expired = await this.prisma.dispatchAttempt.findMany({
      where: {
        status: DispatchStatus.OFFERED,
        expiresAt: { lt: new Date() },
      },
    });

    await this.prisma.dispatchAttempt.updateMany({
      where: {
        id: { in: expired.map((attempt) => attempt.id) },
        status: DispatchStatus.OFFERED,
        expiresAt: { lt: new Date() },
      },
      data: { status: DispatchStatus.EXPIRED },
    });

    const searching = await this.prisma.order.findMany({
      where: {
        status: OrderStatus.SEARCHING,
        dispatchAttempts: {
          none: {
            status: DispatchStatus.OFFERED,
            expiresAt: { gt: new Date() },
          },
        },
      },
      select: { id: true },
      take: 100,
      orderBy: { createdAt: 'asc' },
    });
    const orderIds = [
      ...new Set([
        ...expired.map((attempt) => attempt.orderId),
        ...searching.map((order) => order.id),
      ]),
    ];
    for (const orderId of orderIds) {
      await this.offerToNextBatch(orderId).catch((error) =>
        this.logger.error(`ส่งงานต่อไม่สำเร็จ ${orderId}`, error),
      );
    }
  }
}
