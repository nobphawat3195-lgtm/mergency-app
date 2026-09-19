import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { PaymentStatus } from '@prisma/client';

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

  getPaymentByOrder(orderId: string) {
    return this.prisma.payment.findUnique({ where: { orderId } });
  }
}
