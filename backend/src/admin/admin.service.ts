import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  DispatchStatus,
  OrderStatus,
  ProviderStatus,
  Role,
  WithdrawalStatus,
} from '@prisma/client';
import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';
import { DispatchService } from '../dispatch/dispatch.service';
import { PushService } from '../notifications/push.service';

export function hashPassword(password: string): string {
  const salt = randomBytes(16).toString('hex');
  const derived = scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${derived}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const [salt, expectedHex] = stored.split(':');
  if (!salt || !expectedHex) return false;
  const expected = Buffer.from(expectedHex, 'hex');
  const actual = scryptSync(password, salt, 64);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
    private readonly jwt: JwtService,
    private readonly dispatch: DispatchService,
    private readonly push: PushService,
  ) {}

  async login(
    phone: string,
    password: string,
  ): Promise<{ accessToken: string }> {
    const admin = await this.prisma.adminUser.findUnique({ where: { phone } });
    if (!admin || !verifyPassword(password, admin.passwordHash)) {
      throw new UnauthorizedException('เบอร์โทรหรือรหัสผ่านไม่ถูกต้อง');
    }
    return {
      accessToken: await this.jwt.signAsync({
        sub: admin.id,
        role: Role.ADMIN,
        phone: admin.phone,
      }),
    };
  }

  listProviders(status?: ProviderStatus) {
    return this.prisma.provider.findMany({
      where: status ? { status } : undefined,
      include: {
        serviceCategories: { include: { category: true } },
        vehicleTypes: { include: { vehicleType: true } },
        toolPhotos: true,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async setProviderStatus(providerId: string, status: ProviderStatus) {
    const provider = await this.prisma.provider.findUnique({
      where: { id: providerId },
    });
    if (!provider) throw new NotFoundException('ไม่พบข้อมูลช่าง');

    return this.prisma.provider.update({
      where: { id: providerId },
      data: {
        status,
        // ระงับบัญชีแล้วต้องออฟไลน์ทันที ไม่ให้รับงานใหม่
        isOnline:
          status === ProviderStatus.VERIFIED ? provider.isOnline : false,
      },
    });
  }

  listOrders(status?: OrderStatus) {
    return this.prisma.order.findMany({
      where: status ? { status } : undefined,
      include: {
        category: true,
        subService: true,
        customer: { select: { phone: true, name: true } },
        provider: { select: { realName: true, nickname: true, phone: true } },
        _count: { select: { dispatchAttempts: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
  }

  /** หาช่างใหม่ให้งานที่ไม่มีใครรับ */
  async redispatchOrder(orderId: string) {
    await this.dispatch.redispatch(orderId);
    return this.prisma.order.findUniqueOrThrow({
      where: { id: orderId },
      select: { id: true, orderNo: true, status: true },
    });
  }

  /**
   * ทีมงานยกเลิกงาน (เช่น ไม่มีช่างในพื้นที่ ลูกค้าขอยกเลิกทางโทรศัพท์)
   * ยกเลิกได้เฉพาะก่อนช่างเริ่มซ่อม งานที่เริ่มแล้วต้องให้ช่างปิดงานหรือจัดการเป็นกรณีพิเศษ
   */
  async cancelOrder(orderId: string, reason: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');

    const cancellable: OrderStatus[] = [
      OrderStatus.CREATED,
      OrderStatus.SEARCHING,
      OrderStatus.NO_MATCH,
      OrderStatus.MATCHED,
      OrderStatus.EN_ROUTE,
    ];
    const cancelled = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.order.updateMany({
        where: { id: orderId, status: { in: cancellable } },
        data: {
          status: OrderStatus.CANCELLED,
          cancelledAt: new Date(),
          cancelReason: reason,
        },
      });
      if (updated.count !== 1) return false;
      await tx.dispatchAttempt.updateMany({
        where: { orderId, status: DispatchStatus.OFFERED },
        data: { status: DispatchStatus.EXPIRED },
      });
      return true;
    });
    if (!cancelled) {
      throw new BadRequestException(
        'งานนี้เริ่มซ่อมหรือปิดไปแล้ว ยกเลิกไม่ได้',
      );
    }
    void this.push.cancelledByAdmin(
      order.customerId,
      order.providerId,
      order,
      reason,
    );
    return {
      id: order.id,
      orderNo: order.orderNo,
      status: OrderStatus.CANCELLED,
    };
  }

  listWithdrawals(status?: WithdrawalStatus) {
    return this.prisma.withdrawalRequest.findMany({
      where: status ? { status } : undefined,
      include: {
        provider: { select: { realName: true, nickname: true, phone: true } },
      },
      orderBy: { requestedAt: 'desc' },
    });
  }

  markWithdrawalTransferred(id: string, slipUrl?: string, note?: string) {
    return this.wallet.markTransferred(id, slipUrl, note);
  }

  rejectWithdrawal(id: string, note?: string) {
    return this.wallet.rejectWithdrawal(id, note);
  }

  /** ตัวเลขสรุปหน้าแรกของ dashboard */
  async summary() {
    const [
      orderCount,
      completedOrders,
      pendingProviders,
      pendingWithdrawals,
      noMatchOrders,
    ] = await Promise.all([
      this.prisma.order.count(),
      this.prisma.order.findMany({
        where: { status: OrderStatus.COMPLETED },
        select: { priceFinal: true, commissionRate: true },
      }),
      this.prisma.provider.count({
        where: { status: ProviderStatus.PENDING },
      }),
      this.prisma.withdrawalRequest.count({
        where: { status: WithdrawalStatus.REQUESTED },
      }),
      this.prisma.order.count({ where: { status: OrderStatus.NO_MATCH } }),
    ]);

    const commissionRevenue = completedOrders.reduce(
      (sum, order) =>
        sum + Math.round((order.priceFinal ?? 0) * order.commissionRate),
      0,
    );

    return {
      orderCount,
      completedCount: completedOrders.length,
      commissionRevenue,
      pendingProviders,
      pendingWithdrawals,
      noMatchOrders,
    };
  }
}
