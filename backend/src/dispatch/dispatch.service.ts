import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DispatchStatus, OrderStatus, ProviderStatus } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { distanceKm } from '../common/geo';
import {
  DISPATCH_MAX_CANDIDATES,
  DISPATCH_MAX_RADIUS_KM,
  DISPATCH_OFFER_TIMEOUT_MS,
} from '../common/constants';

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

  constructor(private readonly prisma: PrismaService) {}

  /** เริ่มกระจายงาน: หาช่างที่เข้าเงื่อนไข เรียงตามระยะทาง แล้วเสนอให้คนใกล้สุดก่อน */
  async startDispatch(orderId: string): Promise<void> {
    await this.prisma.order.update({
      where: { id: orderId },
      data: { status: OrderStatus.SEARCHING },
    });
    await this.offerToNextCandidate(orderId);
  }

  /** เสนองานให้ช่างคนถัดไปที่ใกล้ที่สุดและยังไม่เคยถูกเสนอ */
  private async offerToNextCandidate(orderId: string): Promise<void> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { dispatchAttempts: true },
    });

    if (!order) return;
    if (
      order.status !== OrderStatus.SEARCHING &&
      order.status !== OrderStatus.CREATED
    ) {
      return;
    }

    if (order.dispatchAttempts.length >= DISPATCH_MAX_CANDIDATES) {
      await this.markNoMatch(orderId);
      return;
    }

    const alreadyOffered = new Set(
      order.dispatchAttempts.map((attempt) => attempt.providerId),
    );

    const candidates = await this.prisma.provider.findMany({
      where: {
        status: ProviderStatus.VERIFIED,
        isOnline: true,
        id: { notIn: [...alreadyOffered] },
        serviceCategories: { some: { categoryId: order.categoryId } },
        vehicleTypes: { some: { vehicleTypeId: order.vehicleTypeId } },
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

    const next = ranked[0];
    if (!next) {
      await this.markNoMatch(orderId);
      return;
    }

    await this.prisma.dispatchAttempt.create({
      data: {
        orderId,
        providerId: next.provider.id,
        rank: order.dispatchAttempts.length + 1,
        distanceKm: next.distance,
        status: DispatchStatus.OFFERED,
        expiresAt: new Date(Date.now() + DISPATCH_OFFER_TIMEOUT_MS),
      },
    });

    this.logger.log(
      `เสนองาน ${order.orderNo} ให้ช่าง ${next.provider.id} (${next.distance.toFixed(1)} กม.)`,
    );

    // TODO: ส่ง push notification ให้ช่างคนนี้
  }

  private async markNoMatch(orderId: string): Promise<void> {
    await this.prisma.order.update({
      where: { id: orderId },
      data: { status: OrderStatus.NO_MATCH },
    });
    this.logger.warn(`ออเดอร์ ${orderId} ไม่มีช่างรับ ส่งต่อให้แอดมิน`);
    // TODO: แจ้งเตือนแอดมิน
  }

  /** ช่างกดรับงาน */
  async accept(orderId: string, providerId: string): Promise<void> {
    const attempt = await this.prisma.dispatchAttempt.findUnique({
      where: { orderId_providerId: { orderId, providerId } },
      include: { order: true },
    });

    if (!attempt || attempt.status !== DispatchStatus.OFFERED) {
      throw new BadRequestException('งานนี้ไม่ได้ถูกเสนอให้คุณ หรือหมดเวลาแล้ว');
    }
    if (attempt.expiresAt.getTime() < Date.now()) {
      throw new BadRequestException('หมดเวลากดรับงานแล้ว');
    }
    if (attempt.order.status !== OrderStatus.SEARCHING) {
      throw new BadRequestException('งานนี้ถูกรับไปแล้ว');
    }

    await this.prisma.$transaction([
      this.prisma.dispatchAttempt.update({
        where: { id: attempt.id },
        data: { status: DispatchStatus.ACCEPTED, respondedAt: new Date() },
      }),
      // ปิดข้อเสนอที่ค้างอยู่ของช่างคนอื่น ไม่ให้เห็นงานที่ถูกรับไปแล้ว
      this.prisma.dispatchAttempt.updateMany({
        where: {
          orderId,
          status: DispatchStatus.OFFERED,
          id: { not: attempt.id },
        },
        data: { status: DispatchStatus.EXPIRED },
      }),
      this.prisma.order.update({
        where: { id: orderId },
        data: {
          providerId,
          status: OrderStatus.MATCHED,
          matchedAt: new Date(),
        },
      }),
    ]);
  }

  /** ช่างกดปฏิเสธ — ส่งต่อคนถัดไปทันทีไม่ต้องรอหมดเวลา */
  async reject(orderId: string, providerId: string): Promise<void> {
    const attempt = await this.prisma.dispatchAttempt.findUnique({
      where: { orderId_providerId: { orderId, providerId } },
    });

    if (!attempt || attempt.status !== DispatchStatus.OFFERED) {
      throw new BadRequestException('งานนี้ไม่ได้ถูกเสนอให้คุณ');
    }

    await this.prisma.dispatchAttempt.update({
      where: { id: attempt.id },
      data: { status: DispatchStatus.REJECTED, respondedAt: new Date() },
    });

    await this.offerToNextCandidate(orderId);
  }

  /** งานที่ถูกเสนอให้ช่างคนนี้และยังไม่หมดเวลา */
  async listOffersForProvider(providerId: string) {
    return this.prisma.dispatchAttempt.findMany({
      where: {
        providerId,
        status: DispatchStatus.OFFERED,
        expiresAt: { gt: new Date() },
      },
      include: {
        order: {
          include: {
            category: true,
            subService: true,
            vehicleType: true,
            photos: true,
          },
        },
      },
      orderBy: { offeredAt: 'desc' },
    });
  }

  /** ตรวจข้อเสนอที่หมดเวลาทุก 30 วินาที แล้วส่งงานต่อให้ช่างคนถัดไป */
  @Cron(CronExpression.EVERY_30_SECONDS)
  async expireStaleOffers(): Promise<void> {
    const expired = await this.prisma.dispatchAttempt.findMany({
      where: {
        status: DispatchStatus.OFFERED,
        expiresAt: { lt: new Date() },
      },
    });

    for (const attempt of expired) {
      await this.prisma.dispatchAttempt.update({
        where: { id: attempt.id },
        data: { status: DispatchStatus.EXPIRED },
      });
      await this.offerToNextCandidate(attempt.orderId);
    }
  }
}
