import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  OrderStatus,
  PaymentMethod,
  PaymentStatus,
  Role,
} from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';
import { PushService } from '../notifications/push.service';
import { AdminAlertService } from '../notifications/admin-alert.service';
import { UploadsService } from '../uploads/uploads.service';
import { formatBaht } from '../common/money';
import {
  ConfirmedPayment,
  ManualPromptPayGateway,
  PAYMENT_GATEWAY,
  PaymentGateway,
} from './payment-gateway';

export interface PromptPayCharge {
  chargeId: string;
  qrPayload: string;
  amount: number;
  expiresAt: Date;
  hostedUrl: string | null;
  provider: PaymentGateway['name'];
  /** โอนเข้าบัญชีบริษัท: ลูกค้าต้องแนบสลิปให้ทีมงานตรวจ */
  requiresSlip: boolean;
  /** ชื่อบัญชีปลายทางให้ลูกค้าเทียบกับหน้าจอแอปธนาคารก่อนกดโอน */
  payeeName: string | null;
}

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
    @Inject(PAYMENT_GATEWAY) private readonly gateway: PaymentGateway,
    private readonly push: PushService,
    private readonly adminAlert: AdminAlertService,
    private readonly uploads: UploadsService,
  ) {}

  get provider(): PaymentGateway['name'] {
    return this.gateway.name;
  }

  /**
   * สร้าง QR พร้อมเพย์สำหรับออเดอร์ที่ปิดงานแล้ว
   *
   * การแสดง QR ไม่ใช่การชำระสำเร็จ สถานะเปลี่ยนเป็น PAID ได้เฉพาะจาก webhook ที่ตรวจลายเซ็น
   * ของ gateway แล้ว (markPaidFromGateway) หรือช่างยืนยันรับเงินสด
   */
  async createPromptPayCharge(orderId: string): Promise<PromptPayCharge> {
    if (this.gateway.name === 'stub' && process.env.NODE_ENV === 'production') {
      throw new ServiceUnavailableException(
        'พร้อมเพย์ออนไลน์ยังไม่เปิดใช้งาน กรุณาเลือกชำระเงินสดกับช่าง',
      );
    }
    const payment = await this.prisma.payment.findUnique({
      where: { orderId },
      include: { order: { select: { orderNo: true, status: true } } },
    });
    if (!payment) {
      throw new NotFoundException('ออเดอร์นี้ยังไม่มีรายการชำระเงิน');
    }
    if (payment.status === PaymentStatus.PAID) {
      throw new BadRequestException('ออเดอร์นี้ชำระเงินแล้ว');
    }
    if (payment.order.status !== OrderStatus.COMPLETED) {
      throw new BadRequestException('ชำระเงินได้หลังช่างปิดงานแล้ว');
    }

    let qr;
    try {
      qr = await this.gateway.createPromptPay({
        paymentId: payment.id,
        orderId,
        orderNo: payment.order.orderNo,
        amount: payment.amount,
        previousChargeId: payment.chargeId,
      });
    } catch (error) {
      this.logger.error(
        `สร้าง QR พร้อมเพย์ไม่สำเร็จ (${orderId}): ${String(error)}`,
      );
      throw new ServiceUnavailableException(
        'สร้าง QR พร้อมเพย์ไม่สำเร็จ กรุณาลองใหม่ หรือชำระเงินสดกับช่าง',
      );
    }

    await this.prisma.payment.update({
      where: { id: payment.id },
      data: { chargeId: qr.chargeId, method: PaymentMethod.PROMPTPAY },
    });

    return {
      chargeId: qr.chargeId,
      qrPayload: qr.qrPayload,
      amount: payment.amount,
      expiresAt: qr.expiresAt,
      hostedUrl: qr.hostedUrl,
      provider: this.gateway.name,
      requiresSlip: this.gateway instanceof ManualPromptPayGateway,
      payeeName:
        this.gateway instanceof ManualPromptPayGateway
          ? this.gateway.payeeName
          : null,
    };
  }

  /**
   * ลูกค้าแนบสลิปโอนพร้อมเพย์ (โหมดโอนเข้าบัญชีบริษัท)
   * ยังไม่ถือว่าจ่ายแล้วจนกว่าแอดมินตรวจยอดเข้าบัญชีจริงแล้วกดยืนยัน
   */
  async submitSlip(orderId: string, customerId: string, slipUrl: string) {
    if (!(this.gateway instanceof ManualPromptPayGateway)) {
      throw new BadRequestException('ระบบชำระเงินนี้ไม่ต้องแนบสลิป');
    }
    this.uploads.assertOwnedUploads([slipUrl], customerId, 'PAYMENT_SLIP');
    const payment = await this.prisma.payment.findUnique({
      where: { orderId },
      include: {
        order: { select: { customerId: true, status: true, orderNo: true } },
      },
    });
    if (!payment || payment.order.customerId !== customerId) {
      throw new NotFoundException('ไม่พบรายการชำระเงินนี้');
    }
    if (payment.order.status !== OrderStatus.COMPLETED) {
      throw new BadRequestException('แนบสลิปได้หลังช่างปิดงานแล้ว');
    }
    const updated = await this.prisma.payment.updateMany({
      where: { id: payment.id, status: { not: PaymentStatus.PAID } },
      data: {
        slipUrl,
        slipSubmittedAt: new Date(),
        slipRejectReason: null,
        method: PaymentMethod.PROMPTPAY,
      },
    });
    if (updated.count !== 1) {
      throw new BadRequestException('ออเดอร์นี้ชำระเงินแล้ว');
    }
    void this.adminAlert.slipSubmitted(
      payment.order.orderNo,
      formatBaht(payment.amount),
    );
    return { submitted: true };
  }

  /** รายการสลิปที่รอแอดมินตรวจ เรียงจากเก่าสุด */
  listSlipsForReview() {
    return this.prisma.payment.findMany({
      where: {
        status: PaymentStatus.PENDING,
        slipSubmittedAt: { not: null },
      },
      include: {
        order: {
          select: {
            id: true,
            orderNo: true,
            customer: { select: { phone: true } },
            provider: { select: { nickname: true } },
          },
        },
      },
      orderBy: { slipSubmittedAt: 'asc' },
    });
  }

  /**
   * แอดมินตรวจแล้วว่ายอดเข้าบัญชีจริง: บันทึก PAID และเครดิตรายได้ช่างครั้งเดียว
   * กดซ้ำได้ผลเหมือนเดิม
   */
  async confirmSlip(paymentId: string) {
    const payment = await this.prisma.payment.findUnique({
      where: { id: paymentId },
    });
    if (!payment) throw new NotFoundException('ไม่พบรายการชำระเงินนี้');
    if (payment.status === PaymentStatus.PAID) return { status: 'PAID' };
    if (!payment.slipSubmittedAt) {
      throw new BadRequestException('ลูกค้ายังไม่ได้แนบสลิป');
    }
    const updated = await this.prisma.payment.updateMany({
      where: { id: payment.id, status: { not: PaymentStatus.PAID } },
      data: {
        status: PaymentStatus.PAID,
        method: PaymentMethod.PROMPTPAY,
        paidAt: new Date(),
      },
    });
    if (updated.count > 0) {
      await this.wallet.creditOrderEarning(payment.orderId);
      void this.notifyPaid(payment.orderId, payment.amount, 'PROMPTPAY');
    }
    return { status: 'PAID' };
  }

  /** สลิปไม่ถูกต้อง/ยอดไม่เข้า: แจ้งลูกค้าให้แนบใหม่ งานยังค้างชำระ */
  async rejectSlip(paymentId: string, reason: string) {
    const payment = await this.prisma.payment.findUnique({
      where: { id: paymentId },
      include: {
        order: { select: { id: true, orderNo: true, customerId: true } },
      },
    });
    if (!payment) throw new NotFoundException('ไม่พบรายการชำระเงินนี้');
    const updated = await this.prisma.payment.updateMany({
      where: { id: payment.id, status: { not: PaymentStatus.PAID } },
      data: {
        slipSubmittedAt: null,
        slipRejectReason: reason,
      },
    });
    if (updated.count !== 1) {
      throw new BadRequestException('รายการนี้ยืนยันชำระแล้ว ปฏิเสธไม่ได้');
    }
    void this.push.slipRejected(
      payment.order.customerId,
      payment.order,
      reason,
    );
    return { rejected: true };
  }

  /**
   * บันทึกว่าชำระสำเร็จตามผลจาก gateway ที่ตรวจลายเซ็นแล้ว แล้วเครดิตรายได้ให้ช่าง
   *
   * จับคู่ด้วย paymentId ใน metadata (ไม่ใช่ chargeId ล่าสุด) เพราะลูกค้าอาจสแกน QR ใบก่อน
   * และต้องได้ยอดตรงกับที่ต้องจ่ายเป็นเงินบาทเท่านั้น ไม่งั้นไม่ถือว่าจ่ายแล้ว
   * เรียกซ้ำได้ (webhook ส่งซ้ำ) ผลเหมือนเดิม
   */
  async markPaidFromGateway(
    confirmed: ConfirmedPayment,
  ): Promise<'paid' | 'ignored'> {
    const payment = await this.prisma.payment.findUnique({
      where: { id: confirmed.paymentId },
    });
    if (!payment) {
      this.logger.warn(
        `webhook อ้างถึง payment ที่ไม่มีอยู่: ${confirmed.paymentId}`,
      );
      return 'ignored';
    }
    if (payment.status === PaymentStatus.PAID) return 'paid';
    if (
      confirmed.currency.toLowerCase() !== 'thb' ||
      confirmed.amountReceived !== payment.amount
    ) {
      this.logger.error(
        `ยอดไม่ตรง payment ${payment.id}: ต้องได้ ${payment.amount} THB-satang ได้ ${confirmed.amountReceived} ${confirmed.currency}`,
      );
      return 'ignored';
    }

    const updated = await this.prisma.payment.updateMany({
      where: { id: payment.id, status: { not: PaymentStatus.PAID } },
      data: {
        status: PaymentStatus.PAID,
        method: PaymentMethod.PROMPTPAY,
        chargeId: confirmed.chargeId,
        paidAt: new Date(),
      },
    });
    if (updated.count > 0) {
      await this.wallet.creditOrderEarning(payment.orderId);
      void this.notifyPaid(payment.orderId, payment.amount, 'PROMPTPAY');
    }
    return 'paid';
  }

  /**
   * webhook แบบ HMAC เดิม ใช้ตอนพัฒนากับ gateway stub เท่านั้น
   * ห้ามเปิดให้เรียกจากฝั่ง client โดยตรง
   */
  async markPaid(chargeId: string): Promise<void> {
    const payment = await this.prisma.payment.findFirst({
      where: { chargeId },
    });
    if (!payment) throw new NotFoundException('ไม่พบรายการชำระเงินนี้');
    await this.markPaidFromGateway({
      paymentId: payment.id,
      chargeId,
      amountReceived: payment.amount,
      currency: 'thb',
    });
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
    // ช่างรับเงินสดเต็มจำนวนแล้ว: หักค่าธรรมเนียมจากกระเป๋า ไม่ใช่เครดิตรายได้เพิ่ม
    await this.wallet.chargeCashCommission(orderId);
    void this.notifyPaid(orderId, payment.amount, 'CASH');
  }

  private async notifyPaid(
    orderId: string,
    amount: number,
    method: 'PROMPTPAY' | 'CASH',
  ): Promise<void> {
    const order = await this.prisma.order
      .findUnique({
        where: { id: orderId },
        select: { id: true, orderNo: true, customerId: true, providerId: true },
      })
      .catch(() => null);
    if (!order) return;
    await this.push.paid(
      order.customerId,
      order.providerId,
      order,
      amount,
      method,
    );
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
