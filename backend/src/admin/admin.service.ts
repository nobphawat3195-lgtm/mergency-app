import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  AdminRole,
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
import { AdminAuditService } from './admin-access';

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

/** ข้อมูลแอดมินที่ส่งออกได้ (ไม่มี passwordHash) */
const ADMIN_PUBLIC_FIELDS = {
  id: true,
  phone: true,
  name: true,
  role: true,
  disabledAt: true,
  createdAt: true,
} as const;

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
    private readonly jwt: JwtService,
    private readonly dispatch: DispatchService,
    private readonly push: PushService,
    private readonly audit: AdminAuditService,
  ) {}

  async login(
    phone: string,
    password: string,
  ): Promise<{ accessToken: string; role: AdminRole; name: string }> {
    const admin = await this.prisma.adminUser.findUnique({ where: { phone } });
    if (!admin || !verifyPassword(password, admin.passwordHash)) {
      throw new UnauthorizedException('เบอร์โทรหรือรหัสผ่านไม่ถูกต้อง');
    }
    if (admin.disabledAt) {
      throw new UnauthorizedException('บัญชีนี้ถูกปิดแล้ว ติดต่อเจ้าของระบบ');
    }
    void this.audit.record(admin, 'LOGIN');
    return {
      accessToken: await this.jwt.signAsync({
        sub: admin.id,
        role: Role.ADMIN,
        phone: admin.phone,
      }),
      role: admin.role,
      name: admin.name,
    };
  }

  // ---------- ทีมงาน ----------

  listAdmins() {
    return this.prisma.adminUser.findMany({
      select: ADMIN_PUBLIC_FIELDS,
      orderBy: { createdAt: 'asc' },
    });
  }

  async createAdmin(input: {
    phone: string;
    name: string;
    password: string;
    role: AdminRole;
  }) {
    const exists = await this.prisma.adminUser.findUnique({
      where: { phone: input.phone },
      select: { id: true },
    });
    if (exists) throw new BadRequestException('เบอร์นี้มีบัญชีแอดมินแล้ว');
    return this.prisma.adminUser.create({
      data: {
        phone: input.phone,
        name: input.name.trim(),
        passwordHash: hashPassword(input.password),
        role: input.role,
      },
      select: ADMIN_PUBLIC_FIELDS,
    });
  }

  /**
   * เปลี่ยนสิทธิ์ ปิด/เปิดบัญชี หรือตั้งรหัสผ่านใหม่
   * ห้ามลดสิทธิ์หรือปิดบัญชีตัวเอง และต้องเหลือเจ้าของที่ใช้งานได้อย่างน้อย 1 คนเสมอ
   */
  async updateAdmin(
    actorId: string,
    targetId: string,
    input: { role?: AdminRole; disabled?: boolean; password?: string },
  ) {
    const target = await this.prisma.adminUser.findUnique({
      where: { id: targetId },
    });
    if (!target) throw new NotFoundException('ไม่พบบัญชีแอดมินนี้');
    const demoting =
      input.role === AdminRole.STAFF && target.role === AdminRole.OWNER;
    const disabling = input.disabled === true && !target.disabledAt;
    if (actorId === targetId && (demoting || disabling)) {
      throw new BadRequestException('ลดสิทธิ์หรือปิดบัญชีของตัวเองไม่ได้');
    }
    if (target.role === AdminRole.OWNER && (demoting || disabling)) {
      const owners = await this.prisma.adminUser.count({
        where: { role: AdminRole.OWNER, disabledAt: null },
      });
      if (owners <= 1) {
        throw new BadRequestException(
          'ต้องมีเจ้าของที่ใช้งานได้อย่างน้อย 1 คน',
        );
      }
    }
    return this.prisma.adminUser.update({
      where: { id: targetId },
      data: {
        role: input.role,
        disabledAt:
          input.disabled === undefined
            ? undefined
            : input.disabled
              ? (target.disabledAt ?? new Date())
              : null,
        passwordHash: input.password ? hashPassword(input.password) : undefined,
      },
      select: ADMIN_PUBLIC_FIELDS,
    });
  }

  /** แชทของงาน ให้แอดมินเปิดอ่านกรณีมีปัญหา (controller บันทึก audit ทุกครั้งที่เปิด) */
  async listOrderMessages(orderId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { id: true, orderNo: true },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    const messages = await this.prisma.orderMessage.findMany({
      where: { orderId },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        sender: true,
        text: true,
        imageUrl: true,
        createdAt: true,
      },
    });
    return { orderNo: order.orderNo, messages };
  }

  /**
   * หมวดบริการและบริการย่อยทั้งหมด (รวมที่ปิดอยู่) พร้อมจำนวนช่างที่อนุมัติแล้วในหมวด
   * ให้แอดมินเห็นว่าหมวดไหนยังไม่มีช่าง ควรปิดไว้ก่อน
   */
  listCatalog() {
    return this.prisma.serviceCategory.findMany({
      orderBy: { sortOrder: 'asc' },
      include: {
        subServices: { orderBy: { sortOrder: 'asc' } },
        _count: {
          select: {
            providers: {
              where: {
                provider: {
                  status: ProviderStatus.VERIFIED,
                  deletedAt: null,
                },
              },
            },
          },
        },
      },
    });
  }

  async setCategoryActive(id: string, active: boolean) {
    const found = await this.prisma.serviceCategory.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!found) throw new NotFoundException('ไม่พบหมวดบริการ');
    return this.prisma.serviceCategory.update({
      where: { id },
      data: { active },
    });
  }

  async setSubServiceActive(id: string, active: boolean) {
    const found = await this.prisma.subService.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!found) throw new NotFoundException('ไม่พบบริการย่อย');
    return this.prisma.subService.update({ where: { id }, data: { active } });
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

  async setProviderStatus(
    providerId: string,
    status: ProviderStatus,
    note?: string,
  ) {
    const provider = await this.prisma.provider.findUnique({
      where: { id: providerId },
    });
    if (!provider) throw new NotFoundException('ไม่พบข้อมูลช่าง');
    if (status === ProviderStatus.PENDING) {
      throw new BadRequestException('เลือกอนุมัติ ปฏิเสธ หรือระงับเท่านั้น');
    }
    const reviewNote = note?.trim() || null;
    if (status !== ProviderStatus.VERIFIED && !reviewNote) {
      throw new BadRequestException('กรุณาใส่เหตุผลให้ช่างทราบ');
    }

    const updated = await this.prisma.provider.update({
      where: { id: providerId },
      data: {
        status,
        reviewNote: status === ProviderStatus.VERIFIED ? null : reviewNote,
        reviewedAt: new Date(),
        // ไม่ได้รับอนุมัติต้องออฟไลน์ทันที ไม่ให้รับงานใหม่
        isOnline:
          status === ProviderStatus.VERIFIED ? provider.isOnline : false,
      },
    });
    if (provider.status !== status) {
      void this.push.providerReviewed(
        providerId,
        status === ProviderStatus.VERIFIED,
        reviewNote,
      );
    }
    return updated;
  }

  listOrders(status?: OrderStatus) {
    return this.prisma.order.findMany({
      where: status ? { status } : undefined,
      include: {
        category: true,
        subService: true,
        customer: { select: { phone: true, name: true } },
        provider: { select: { realName: true, nickname: true, phone: true } },
        closePhotos: {
          select: { kind: true, url: true },
          orderBy: { createdAt: 'asc' },
        },
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
      pendingSlips,
      pendingSettlements,
      outstandingDebt,
      completedCount,
    ] = await Promise.all([
      this.prisma.order.count(),
      this.prisma.order.findMany({
        where: { status: OrderStatus.COMPLETED, payment: { status: 'PAID' } },
        select: { priceFinal: true, commissionRate: true },
      }),
      this.prisma.provider.count({
        where: { status: ProviderStatus.PENDING },
      }),
      this.prisma.withdrawalRequest.count({
        where: { status: WithdrawalStatus.REQUESTED },
      }),
      this.prisma.order.count({ where: { status: OrderStatus.NO_MATCH } }),
      this.prisma.payment.count({
        where: { status: 'PENDING', slipSubmittedAt: { not: null } },
      }),
      this.prisma.commissionSettlement.count({ where: { status: 'PENDING' } }),
      this.wallet.totalOutstandingDebt(),
      this.prisma.order.count({ where: { status: OrderStatus.COMPLETED } }),
    ]);

    const commissionRevenue = completedOrders.reduce(
      (sum, order) =>
        sum + Math.round((order.priceFinal ?? 0) * order.commissionRate),
      0,
    );

    return {
      orderCount,
      completedCount,
      commissionRevenue,
      pendingProviders,
      pendingWithdrawals,
      noMatchOrders,
      pendingSlips,
      pendingSettlements,
      /** ค่าบริการที่ช่างค้างจากงานเงินสดรวมกัน (สตางค์) ยังไม่ได้เข้าบัญชีบริษัท */
      outstandingDebt,
    };
  }
}
