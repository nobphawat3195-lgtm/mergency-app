import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  HttpCode,
  Logger,
  NotFoundException,
  Param,
  Post,
  RawBodyRequest,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import Stripe from 'stripe';
import { IsString } from 'class-validator';
import { Role } from '@prisma/client';
import { createHmac, timingSafeEqual } from 'node:crypto';

import { PaymentsService } from './payments.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';
import { PrismaService } from '../prisma/prisma.service';
import { readSecret } from '../config/environment';
import { confirmedPaymentFromStripeEvent } from './payment-gateway';

export class GatewayWebhookDto {
  @IsString()
  chargeId!: string;

  @IsString()
  signature!: string;
}

@Controller('payments')
export class PaymentsController {
  private readonly logger = new Logger(PaymentsController.name);

  constructor(
    private readonly payments: PaymentsService,
    private readonly prisma: PrismaService,
  ) {}

  @Post('orders/:orderId/promptpay')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.CUSTOMER)
  async createCharge(
    @CurrentUser() user: JwtPayload,
    @Param('orderId') orderId: string,
  ) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { customerId: true },
    });
    if (!order || order.customerId !== user.sub) {
      throw new ForbiddenException('ชำระเงินให้ออเดอร์ของคนอื่นไม่ได้');
    }
    return this.payments.createPromptPayCharge(orderId);
  }

  @Get('orders/:orderId')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.CUSTOMER, Role.PROVIDER)
  getPayment(
    @CurrentUser() user: JwtPayload,
    @Param('orderId') orderId: string,
  ) {
    return this.payments.getPaymentForActor(orderId, user);
  }

  /**
   * Webhook สำหรับ payment gateway เรียกเข้ามาเมื่อชำระเงินสำเร็จ
   *
   * signature = HMAC-SHA256(chargeId, PAYMENT_WEBHOOK_SECRET)
   * เมื่อเลือก gateway จริงให้ adapter ของ gateway แปลง event แล้วส่งรูปแบบนี้เข้ามา
   */
  @Post('webhook')
  async webhook(@Body() dto: GatewayWebhookDto) {
    // ใช้ได้เฉพาะตอนพัฒนากับ gateway stub เมื่อใช้ Stripe ผลการจ่ายต้องมาจาก Stripe เท่านั้น
    if (this.payments.provider !== 'stub') {
      throw new NotFoundException();
    }
    const secret = readSecret(
      'PAYMENT_WEBHOOK_SECRET',
      'dev-payment-webhook-secret',
    );
    const expected = createHmac('sha256', secret).update(dto.chargeId).digest();
    let actual: Buffer;
    try {
      actual = Buffer.from(dto.signature, 'hex');
    } catch (_) {
      throw new ForbiddenException('ลายเซ็น webhook ไม่ถูกต้อง');
    }
    if (
      actual.length !== expected.length ||
      !timingSafeEqual(actual, expected)
    ) {
      throw new ForbiddenException('ลายเซ็น webhook ไม่ถูกต้อง');
    }
    await this.payments.markPaid(dto.chargeId);
    return { ok: true };
  }

  /**
   * Stripe webhook: ตรวจลายเซ็นด้วย STRIPE_WEBHOOK_SECRET กับ body ดิบก่อนเชื่อผลใด ๆ
   * ตั้งใน Stripe Dashboard > Developers > Webhooks ให้ส่ง payment_intent.succeeded มาที่
   * https://<api-domain>/api/payments/stripe/webhook
   */
  @Post('stripe/webhook')
  @HttpCode(200)
  async stripeWebhook(
    @Req() request: RawBodyRequest<Request>,
    @Headers('stripe-signature') signature: string | undefined,
  ) {
    const secret = process.env.STRIPE_WEBHOOK_SECRET?.trim();
    if (this.payments.provider !== 'stripe' || !secret) {
      throw new NotFoundException();
    }
    if (!signature || !request.rawBody) {
      throw new BadRequestException('ไม่มีลายเซ็น Stripe');
    }
    let event: Stripe.Event;
    try {
      event = Stripe.webhooks.constructEvent(
        request.rawBody,
        signature,
        secret,
      );
    } catch {
      throw new BadRequestException('ลายเซ็น Stripe ไม่ถูกต้อง');
    }

    const confirmed = confirmedPaymentFromStripeEvent(event);
    if (confirmed) {
      const result = await this.payments.markPaidFromGateway(confirmed);
      this.logger.log(`Stripe ${event.type} ${confirmed.chargeId}: ${result}`);
    }
    // ตอบ 200 ทุก event ที่ลายเซ็นถูก ไม่งั้น Stripe จะส่งซ้ำเรื่อย ๆ
    return { received: true };
  }
}
