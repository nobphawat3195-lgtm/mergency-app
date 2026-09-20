import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsString } from 'class-validator';
import { Role } from '@prisma/client';
import { createHmac, timingSafeEqual } from 'node:crypto';

import { PaymentsService } from './payments.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';
import { PrismaService } from '../prisma/prisma.service';
import { readSecret } from '../config/environment';

export class GatewayWebhookDto {
  @IsString()
  chargeId!: string;

  @IsString()
  signature!: string;
}

@Controller('payments')
export class PaymentsController {
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

  @Post('orders/:orderId/cash/confirm')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.PROVIDER)
  async confirmCash(
    @CurrentUser() user: JwtPayload,
    @Param('orderId') orderId: string,
  ) {
    await this.payments.confirmCashPayment(orderId, user.sub);
    return { ok: true };
  }

  /**
   * Webhook สำหรับ payment gateway เรียกเข้ามาเมื่อชำระเงินสำเร็จ
   *
   * signature = HMAC-SHA256(chargeId, PAYMENT_WEBHOOK_SECRET)
   * เมื่อเลือก gateway จริงให้ adapter ของ gateway แปลง event แล้วส่งรูปแบบนี้เข้ามา
   */
  @Post('webhook')
  async webhook(@Body() dto: GatewayWebhookDto) {
    const secret = readSecret(
      'PAYMENT_WEBHOOK_SECRET',
      'dev-payment-webhook-secret',
    );
    const expected = createHmac('sha256', secret)
      .update(dto.chargeId)
      .digest();
    let actual: Buffer;
    try {
      actual = Buffer.from(dto.signature, 'hex');
    } catch (_) {
      throw new ForbiddenException('ลายเซ็น webhook ไม่ถูกต้อง');
    }
    if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
      throw new ForbiddenException('ลายเซ็น webhook ไม่ถูกต้อง');
    }
    await this.payments.markPaid(dto.chargeId);
    return { ok: true };
  }
}
