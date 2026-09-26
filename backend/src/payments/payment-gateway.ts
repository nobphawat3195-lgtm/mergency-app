import { Logger } from '@nestjs/common';
import Stripe from 'stripe';

import { normalizePromptPayId, promptPayPayload } from './promptpay-qr';

/** ข้อมูลที่ gateway ต้องใช้สร้าง QR พร้อมเพย์ 1 รายการ */
export interface PromptPayRequest {
  paymentId: string;
  orderId: string;
  orderNo: string;
  /** สตางค์ */
  amount: number;
  /** รายการเดิมที่ยังเปิดอยู่ ยกเลิกก่อนสร้างใหม่ กันลูกค้าสแกน QR เก่าซ้ำ */
  previousChargeId?: string | null;
}

export interface PromptPayQr {
  chargeId: string;
  /** ข้อความ EMVCo สำหรับวาด QR ในแอป */
  qrPayload: string;
  /** หน้าเว็บ QR ของ gateway (ถ้ามี) สำรองไว้เปิดในเบราว์เซอร์ */
  hostedUrl: string | null;
  expiresAt: Date;
}

/** ผลการชำระที่ gateway ยืนยันแล้ว (มาจาก webhook ที่ตรวจลายเซ็นแล้วเท่านั้น) */
export interface ConfirmedPayment {
  paymentId: string;
  chargeId: string;
  /** สตางค์ ที่ได้รับจริง */
  amountReceived: number;
  currency: string;
}

export interface PaymentGateway {
  readonly name: 'stub' | 'stripe' | 'promptpay_manual';
  createPromptPay(request: PromptPayRequest): Promise<PromptPayQr>;
}

/** ใช้ตอนพัฒนาเท่านั้น QR นี้สแกนจ่ายจริงไม่ได้ */
export class StubPaymentGateway implements PaymentGateway {
  readonly name = 'stub' as const;
  private readonly logger = new Logger('StubPaymentGateway');

  async createPromptPay(request: PromptPayRequest): Promise<PromptPayQr> {
    this.logger.warn(
      'ใช้ PromptPay แบบ stub อยู่ ตั้ง PAYMENT_PROVIDER=stripe ก่อนใช้งานจริง',
    );
    const chargeId = `stub_${request.paymentId}`;
    return {
      chargeId,
      qrPayload: `STUB-QR|${chargeId}|${request.amount}`,
      hostedUrl: null,
      expiresAt: new Date(Date.now() + 15 * 60 * 1000),
    };
  }
}

/**
 * พร้อมเพย์โอนตรงเข้าบัญชีของบริษัท (ไม่มีค่าธรรมเนียม)
 *
 * QR ล็อกยอดเงินตามงาน แต่ระบบรู้ไม่ได้เองว่าเงินเข้าแล้ว ลูกค้าต้องแนบสลิป
 * แล้วแอดมินตรวจยอดในบัญชีจริงก่อนกดยืนยัน สถานะจึงเป็น PAID
 */
export class ManualPromptPayGateway implements PaymentGateway {
  readonly name = 'promptpay_manual' as const;

  constructor(
    private readonly promptPayId: string,
    readonly payeeName: string,
  ) {
    normalizePromptPayId(promptPayId);
  }

  async createPromptPay(request: PromptPayRequest): Promise<PromptPayQr> {
    return {
      chargeId: `manual_${request.paymentId}`,
      qrPayload: promptPayPayload(this.promptPayId, request.amount),
      hostedUrl: null,
      // QR แบบนี้ไม่หมดอายุฝั่งธนาคาร แต่ให้แอปขอใหม่ทุกวันเผื่อยอดงานเปลี่ยน
      expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
    };
  }
}

/**
 * พร้อมเพย์ผ่าน Stripe PaymentIntent
 *
 * สร้าง PaymentIntent แบบ promptpay แล้วยืนยันทันที Stripe จะคืน QR ใน
 * next_action.promptpay_display_qr_code ส่วนผลการจ่ายจริงมาทาง webhook เท่านั้น
 * (payment_intent.succeeded) ห้ามเชื่อผลจากฝั่งแอป
 */
export class StripePaymentGateway implements PaymentGateway {
  readonly name = 'stripe' as const;
  private readonly logger = new Logger('StripePaymentGateway');

  constructor(
    private readonly stripe: Stripe,
    /** Stripe บังคับอีเมลผู้จ่ายสำหรับพร้อมเพย์ แอปไม่ได้เก็บอีเมลลูกค้า จึงใช้อีเมลบริษัท */
    private readonly billingEmail: string,
  ) {}

  async createPromptPay(request: PromptPayRequest): Promise<PromptPayQr> {
    if (request.previousChargeId?.startsWith('pi_')) {
      await this.cancelIfOpen(request.previousChargeId);
    }

    const intent = await this.stripe.paymentIntents.create(
      {
        amount: request.amount,
        currency: 'thb',
        payment_method_types: ['promptpay'],
        payment_method_data: {
          type: 'promptpay',
          billing_details: { email: this.billingEmail },
        },
        confirm: true,
        description: `FixGo ${request.orderNo}`,
        metadata: {
          paymentId: request.paymentId,
          orderId: request.orderId,
          orderNo: request.orderNo,
        },
      },
      // กดซ้ำเร็ว ๆ ได้ QR เดิม ไม่สร้างรายการซ้อน
      {
        idempotencyKey: `promptpay:${request.paymentId}:${Math.floor(Date.now() / 60_000)}`,
      },
    );

    const qr = intent.next_action?.promptpay_display_qr_code;
    if (intent.status !== 'requires_action' || !qr?.data) {
      this.logger.error(
        `Stripe ไม่คืน QR พร้อมเพย์ (intent ${intent.id} status ${intent.status})`,
      );
      throw new Error('สร้าง QR พร้อมเพย์ไม่สำเร็จ');
    }

    return {
      chargeId: intent.id,
      qrPayload: qr.data,
      hostedUrl: qr.hosted_instructions_url ?? null,
      // QR พร้อมเพย์ของ Stripe ใช้ได้ไม่เกินราว 1 ชั่วโมง แจ้งผู้ใช้สั้นกว่าเพื่อความปลอดภัย
      expiresAt: new Date(Date.now() + 15 * 60 * 1000),
    };
  }

  private async cancelIfOpen(intentId: string) {
    try {
      const intent = await this.stripe.paymentIntents.retrieve(intentId);
      if (
        intent.status === 'requires_action' ||
        intent.status === 'requires_payment_method'
      ) {
        await this.stripe.paymentIntents.cancel(intentId);
      }
    } catch (error) {
      // ยกเลิกไม่ได้ไม่ควรขวางการสร้าง QR ใหม่ webhook จับคู่ด้วย paymentId อยู่แล้ว
      this.logger.warn(
        `ยกเลิก PaymentIntent เดิม ${intentId} ไม่สำเร็จ: ${String(error)}`,
      );
    }
  }
}

/**
 * แปลง Stripe event ที่ตรวจลายเซ็นแล้วเป็นผลการชำระ คืน null ถ้าไม่ใช่ event ที่เราสนใจ
 * แยกออกมาเป็นฟังก์ชันล้วนเพื่อทดสอบได้โดยไม่ต้องต่อ Stripe
 */
export function confirmedPaymentFromStripeEvent(
  event: Stripe.Event,
): ConfirmedPayment | null {
  if (event.type !== 'payment_intent.succeeded') return null;
  const intent = event.data.object;
  const paymentId = intent.metadata?.paymentId;
  if (!paymentId) return null;
  return {
    paymentId,
    chargeId: intent.id,
    amountReceived: intent.amount_received,
    currency: intent.currency,
  };
}

export function createPaymentGateway(): PaymentGateway {
  const provider = (process.env.PAYMENT_PROVIDER ?? 'stub').trim();
  if (provider === 'stripe') {
    const secretKey = process.env.STRIPE_SECRET_KEY?.trim();
    if (!secretKey)
      throw new Error('PAYMENT_PROVIDER=stripe ต้องตั้ง STRIPE_SECRET_KEY');
    const email =
      process.env.STRIPE_BILLING_EMAIL?.trim() ||
      process.env.LEGAL_CONTACT_EMAIL?.trim();
    if (!email) {
      throw new Error(
        'PAYMENT_PROVIDER=stripe ต้องตั้ง STRIPE_BILLING_EMAIL (Stripe บังคับอีเมลสำหรับพร้อมเพย์)',
      );
    }
    return new StripePaymentGateway(new Stripe(secretKey), email);
  }
  if (provider === 'promptpay_manual') {
    const id = process.env.PROMPTPAY_ID?.trim();
    const name = process.env.PROMPTPAY_NAME?.trim();
    if (!id || !name) {
      throw new Error(
        'PAYMENT_PROVIDER=promptpay_manual ต้องตั้ง PROMPTPAY_ID และ PROMPTPAY_NAME',
      );
    }
    return new ManualPromptPayGateway(id, name);
  }
  return new StubPaymentGateway();
}

export const PAYMENT_GATEWAY = Symbol('PAYMENT_GATEWAY');
