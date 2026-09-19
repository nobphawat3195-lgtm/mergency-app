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

import { PaymentsService } from './payments.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';
import { PrismaService } from '../prisma/prisma.service';

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
  getPayment(@Param('orderId') orderId: string) {
    return this.payments.getPaymentByOrder(orderId);
  }

  /**
   * Webhook สำหรับ payment gateway เรียกเข้ามาเมื่อชำระเงินสำเร็จ
   *
   * ยังเป็น stub — ต้องเปลี่ยนไปตรวจลายเซ็นจริงของ gateway ก่อนใช้งาน production
   * มิฉะนั้นใครก็ยิง endpoint นี้เพื่อทำให้ออเดอร์เป็นจ่ายแล้วได้
   */
  @Post('webhook')
  async webhook(@Body() dto: GatewayWebhookDto) {
    const expected = process.env.PAYMENT_WEBHOOK_SECRET;
    if (!expected || dto.signature !== expected) {
      throw new ForbiddenException('ลายเซ็น webhook ไม่ถูกต้อง');
    }
    await this.payments.markPaid(dto.chargeId);
    return { ok: true };
  }
}
