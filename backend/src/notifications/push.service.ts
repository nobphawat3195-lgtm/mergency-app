import { Inject, Injectable, Logger } from '@nestjs/common';
import { DevicePlatform, Role } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { formatBaht } from '../common/money';
import { PUSH_SENDER, PushMessage, PushSender } from './push-sender';
import { OrderEventsService } from './order-events.service';

/** ประเภทแจ้งเตือน แอปใช้ตัดสินว่ากดแล้วเปิดหน้าไหน */
export type PushType =
  | 'OFFER'
  | 'NO_MATCH'
  | 'MATCHED'
  | 'EN_ROUTE'
  | 'IN_PROGRESS'
  | 'QUOTE_PROPOSED'
  | 'QUOTE_APPROVED'
  | 'QUOTE_REJECTED'
  | 'COMPLETED'
  | 'CANCELLED'
  | 'PAID';

interface OrderRef {
  id: string;
  orderNo: string;
}

/**
 * แจ้งเตือนผู้ใช้เมื่อสถานะงานเปลี่ยน
 *
 * ทุกเมธอดไม่ throw: push เป็นช่องทางเสริม ห้ามทำให้การรับงาน/ปิดงาน/ชำระเงินล้มเหลว
 * แอปยังดึงสถานะจาก API เป็นหลักเสมอ ข้อความ push ไม่ใช่แหล่งความจริง
 */
@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(PUSH_SENDER) private readonly sender: PushSender,
    private readonly events: OrderEventsService,
  ) {}

  async registerDevice(
    userId: string,
    role: Role,
    token: string,
    platform: DevicePlatform,
  ): Promise<void> {
    await this.prisma.deviceToken.upsert({
      where: { token },
      create: { token, platform, role, userId },
      update: { platform, role, userId, lastSeenAt: new Date() },
    });
  }

  async unregisterDevice(userId: string, role: Role, token: string) {
    await this.prisma.deviceToken.deleteMany({
      where: { token, role, userId },
    });
  }

  async removeAllDevices(userId: string, role: Role) {
    await this.prisma.deviceToken.deleteMany({ where: { role, userId } });
  }

  private async sendToUsers(
    role: Role,
    userIds: string[],
    type: PushType,
    order: OrderRef,
    title: string,
    body: string,
  ): Promise<void> {
    // หน้าติดตามงานที่เปิดอยู่ (SSE) ดึงข้อมูลใหม่ทันที แม้ผู้ใช้จะไม่มีโทเคน push
    this.events.emit(order.id, type);
    if (userIds.length === 0) return;
    try {
      const devices = await this.prisma.deviceToken.findMany({
        where: { role, userId: { in: userIds } },
        select: { token: true },
      });
      const message: PushMessage = {
        title,
        body,
        data: { type, orderId: order.id, orderNo: order.orderNo },
      };
      const invalid: string[] = [];
      await Promise.all(
        devices.map(async ({ token }) => {
          try {
            const result = await this.sender.send(token, message);
            if (result === 'invalid') invalid.push(token);
          } catch (error) {
            this.logger.warn(`ส่ง push ไม่สำเร็จ: ${(error as Error).message}`);
          }
        }),
      );
      if (invalid.length > 0) {
        await this.prisma.deviceToken.deleteMany({
          where: { token: { in: invalid } },
        });
      }
    } catch (error) {
      this.logger.error(
        `push ${type} ${order.orderNo} ล้มเหลว`,
        error as Error,
      );
    }
  }

  private toCustomer(
    customerId: string,
    type: PushType,
    order: OrderRef,
    title: string,
    body: string,
  ) {
    return this.sendToUsers(
      Role.CUSTOMER,
      [customerId],
      type,
      order,
      title,
      body,
    );
  }

  private toProvider(
    providerId: string | null,
    type: PushType,
    order: OrderRef,
    title: string,
    body: string,
  ) {
    if (!providerId) return Promise.resolve();
    return this.sendToUsers(
      Role.PROVIDER,
      [providerId],
      type,
      order,
      title,
      body,
    );
  }

  // ---------- เหตุการณ์ของงาน ----------

  offerToProviders(
    providers: { id: string; distanceKm: number }[],
    order: OrderRef & { serviceName: string },
    timeoutSeconds: number,
  ) {
    // ข้อความต่างกันตามระยะทาง จึงส่งทีละคน
    return Promise.all(
      providers.map((provider) =>
        this.sendToUsers(
          Role.PROVIDER,
          [provider.id],
          'OFFER',
          order,
          'มีงานใหม่ใกล้คุณ',
          `${order.serviceName} · ห่าง ${provider.distanceKm.toFixed(1)} กม. กดรับภายใน ${timeoutSeconds} วินาที`,
        ),
      ),
    ).then(() => undefined);
  }

  noMatch(customerId: string, order: OrderRef) {
    return this.toCustomer(
      customerId,
      'NO_MATCH',
      order,
      'ยังไม่พบช่างว่างในตอนนี้',
      'ทีมงาน FixGo จะช่วยหาช่างให้และติดต่อกลับโดยเร็ว',
    );
  }

  matched(customerId: string, order: OrderRef, providerName: string) {
    return this.toCustomer(
      customerId,
      'MATCHED',
      order,
      'ช่างรับงานแล้ว',
      `${providerName} กำลังเตรียมเดินทางไปหาคุณ`,
    );
  }

  enRoute(customerId: string, order: OrderRef) {
    return this.toCustomer(
      customerId,
      'EN_ROUTE',
      order,
      'ช่างกำลังเดินทาง',
      'ติดตามตำแหน่งช่างได้ในแอป',
    );
  }

  inProgress(customerId: string, order: OrderRef) {
    return this.toCustomer(
      customerId,
      'IN_PROGRESS',
      order,
      'ช่างเริ่มงานแล้ว',
      `งาน ${order.orderNo} กำลังดำเนินการ`,
    );
  }

  quoteProposed(customerId: string, order: OrderRef, amountSatang: number) {
    return this.toCustomer(
      customerId,
      'QUOTE_PROPOSED',
      order,
      'ช่างเสนอราคาแล้ว',
      `ราคา ${formatBaht(amountSatang)} รอคุณยืนยันก่อนเริ่มงาน`,
    );
  }

  quoteAnswered(providerId: string | null, order: OrderRef, approved: boolean) {
    return this.toProvider(
      providerId,
      approved ? 'QUOTE_APPROVED' : 'QUOTE_REJECTED',
      order,
      approved ? 'ลูกค้ายืนยันราคาแล้ว' : 'ลูกค้าไม่ยืนยันราคา',
      approved ? 'เริ่มงานได้เลย' : 'คุยกับลูกค้าแล้วเสนอราคาใหม่ได้ในแอป',
    );
  }

  completed(customerId: string, order: OrderRef, amountSatang: number) {
    return this.toCustomer(
      customerId,
      'COMPLETED',
      order,
      'งานเสร็จแล้ว',
      `ยอดชำระ ${formatBaht(amountSatang)} ชำระและให้คะแนนช่างได้ในแอป`,
    );
  }

  cancelledByAdmin(
    customerId: string,
    providerId: string | null,
    order: OrderRef,
    reason: string,
  ) {
    return Promise.all([
      this.toCustomer(
        customerId,
        'CANCELLED',
        order,
        'ทีมงานยกเลิกงานของคุณ',
        reason,
      ),
      this.toProvider(
        providerId,
        'CANCELLED',
        order,
        'งานถูกยกเลิกโดยทีมงาน',
        `งาน ${order.orderNo} ถูกยกเลิกแล้ว ไม่ต้องเดินทางต่อ`,
      ),
    ]).then(() => undefined);
  }

  cancelledByCustomer(providerId: string | null, order: OrderRef) {
    return this.toProvider(
      providerId,
      'CANCELLED',
      order,
      'ลูกค้ายกเลิกงาน',
      `งาน ${order.orderNo} ถูกยกเลิกแล้ว ไม่ต้องเดินทางต่อ`,
    );
  }

  /** PromptPay: แจ้งทั้งสองฝ่าย / เงินสด: ช่างกดยืนยันเองอยู่แล้ว แจ้งแค่ลูกค้า */
  paid(
    customerId: string,
    providerId: string | null,
    order: OrderRef,
    amountSatang: number,
    method: 'PROMPTPAY' | 'CASH',
  ) {
    const amount = formatBaht(amountSatang);
    return Promise.all([
      this.toCustomer(
        customerId,
        'PAID',
        order,
        'ชำระเงินสำเร็จ',
        method === 'PROMPTPAY'
          ? `ได้รับยอด ${amount} แล้ว ขอบคุณที่ใช้บริการ FixGo`
          : `ช่างยืนยันรับเงินสด ${amount} แล้ว ขอบคุณที่ใช้บริการ FixGo`,
      ),
      method === 'PROMPTPAY'
        ? this.toProvider(
            providerId,
            'PAID',
            order,
            'ลูกค้าชำระเงินแล้ว',
            `งาน ${order.orderNo} ยอด ${amount} รายได้เข้ากระเป๋าแล้ว`,
          )
        : Promise.resolve(),
    ]).then(() => undefined);
  }
}
