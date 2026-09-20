import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { OrderStatus, PaymentMethod, PaymentStatus, Role } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';

export interface PromptPayCharge {
  chargeId: string;
  qrPayload: string;
  amount: number;
  expiresAt: Date;
}

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
  ) {}

  /**
   * สร้างรายการชำระเงินพร้อมเพย์สำหรับออเดอร์
   *
   * ยังไม่ได้ต่อ payment gateway จริง — ส่วนนี้เป็น stub ที่คืน payload ปลอม
   * ตอนต่อของจริงให้แทนที่ด้วยการเรียก API ของ gateway แล้วเก็บ chargeId ที่ได้กลับมา
   */
  async createPromptPayCharge(orderId: string): Promise<PromptPayCharge> {
    if (process.env.NODE_ENV === 'production') {
      throw new ServiceUnavailableException(
        'พร้อมเพย์ออนไลน์ยังไม่เปิดใช้งาน กรุณาเลือกชำระเงินสดกับช่าง',
      );
    }
    const payment = await this.prisma.payment.findUnique({
      where: { orderId },
    });
    if (!payment) {
      throw new NotFoundException('ออเดอร์นี้ยังไม่มีรายการชำระเงิน');
    }
    if (payment.status === PaymentStatus.PAID) {
      throw new BadRequestException('ออเดอร์นี้ชำระเงินแล้ว');
    }

    const chargeId = `stub_${payment.id}`;

    await this.prisma.payment.update({
      where: { id: payment.id },
      data: { chargeId },
    });

    this.logger.warn(
      'ใช้ PromptPay แบบ stub อยู่ — ต้องต่อ payment gateway จริงก่อนใช้งานจริง',
    );

    return {
      chargeId,
      qrPayload: `STUB-QR|${chargeId}|${payment.amount}`,
      amount: payment.amount,
      expiresAt: new Date(Date.now() + 15 * 60 * 1000),
    };
  }

  /**
   * ยืนยันว่าชำระเงินสำเร็จ แล้วเครดิตยอดสุทธิเข้ากระเป๋าช่าง
   *
   * ตอนต่อ gateway จริง ให้เรียกจาก webhook handler หลังตรวจลายเซ็นของ gateway แล้ว
   * ห้ามเปิดให้เรียกจากฝั่ง client โดยตรง
   */
  async markPaid(chargeId: string): Promise<void> {
    const payment = await this.prisma.payment.findFirst({
      where: { chargeId },
    });
    if (!payment) throw new NotFoundException('ไม่พบรายการชำระเงินนี้');

    if (payment.status === PaymentStatus.PAID) return;

    await this.prisma.payment.update({
      where: { id: payment.id },
      data: { status: PaymentStatus.PAID, paidAt: new Date() },
    });

    await this.wallet.creditOrderEarning(payment.orderId);
  }

  async confirmCashPayment(orderId: string, providerId: string): Promise<void> {
    const payment = await this.prisma.payment.findUnique({
      where: { orderId },
      include: { order: true },
    });
    if (!payment) throw new NotFoundException('ไม่พบรายการชำระเงินนี้');
    if (payment.order.providerId !== providerId) {
      throw new ForbiddenException('ยืนยันการรับเงินของงานคนอื่นไม่ได้');
    }
    if (payment.order.status !== OrderStatus.COMPLETED) {
      throw new BadRequestException('ยืนยันรับเงินได้หลังปิดงานแล้วเท่านั้น');
    }
    if (payment.status === PaymentStatus.PAID) return;

    await this.prisma.payment.update({
      where: { id: payment.id },
      data: {
        method: PaymentMethod.CASH,
        status: PaymentStatus.PAID,
        paidAt: new Date(),
      },
    });
    await this.wallet.creditOrderEarning(orderId);
  }

  getPaymentByOrder(orderId: string) {
    return this.prisma.payment.findUnique({ where: { orderId } });
  }

  async getPaymentForActor(
    orderId: string,
    actor: { sub: string; role: Role },
  ) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { customerId: true, providerId: true },
    });
    const allowed =
      order &&
      ((actor.role === Role.CUSTOMER && order.customerId === actor.sub) ||
        (actor.role === Role.PROVIDER && order.providerId === actor.sub));
    if (!allowed) throw new NotFoundException('ไม่พบรายการชำระเงินนี้');
    return this.getPaymentByOrder(orderId);
  }
}
