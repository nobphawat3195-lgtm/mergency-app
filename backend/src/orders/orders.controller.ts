import {
  Body,
  Controller,
  Delete,
  Get,
  MessageEvent,
  Param,
  Patch,
  Post,
  Sse,
  UseGuards,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { OrderStatus, Role } from '@prisma/client';

import { OrdersService } from './orders.service';
import {
  CreateOrderDto,
  ProposeQuoteDto,
  RateOrderDto,
  RespondQuoteDto,
  ServiceSuggestionDto,
} from './dto/order.dto';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';
import { OrderEventsService } from '../notifications/order-events.service';
import { OrderAccessGuard } from './order-access.guard';
import { OrderShareService } from './order-share.service';

@Controller('orders')
@UseGuards(JwtAuthGuard, RolesGuard)
export class OrdersController {
  constructor(
    private readonly orders: OrdersService,
    private readonly orderEvents: OrderEventsService,
    private readonly orderShare: OrderShareService,
  ) {}

  @Post()
  @Roles(Role.CUSTOMER)
  create(@CurrentUser() user: JwtPayload, @Body() dto: CreateOrderDto) {
    return this.orders.create(user.sub, dto);
  }

  @Get('mine')
  @Roles(Role.CUSTOMER)
  listMine(@CurrentUser() user: JwtPayload) {
    return this.orders.listForCustomer(user.sub);
  }

  @Get('assigned')
  @Roles(Role.PROVIDER)
  listAssigned(@CurrentUser() user: JwtPayload) {
    return this.orders.listForProvider(user.sub);
  }

  /** สร้าง (หรือคืนลิงก์เดิม) ลิงก์ติดตามงานให้ครอบครัวเปิดดูได้โดยไม่ต้องล็อกอิน */
  @Post(':id/share')
  @Roles(Role.CUSTOMER)
  share(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orderShare.share(id, user.sub);
  }

  /** ยกเลิกลิงก์ติดตาม คนที่มีลิงก์เดิมจะเปิดไม่ได้อีก */
  @Delete(':id/share')
  @Roles(Role.CUSTOMER)
  revokeShare(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orderShare.revoke(id, user.sub);
  }

  @Get(':id')
  @Roles(Role.CUSTOMER, Role.PROVIDER)
  async findOne(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    const { suggestion, ...order } = await this.orders.findAccessibleById(
      id,
      user,
    );
    // ข้อเสนอแนะถึงทีม FixGo ช่างไม่ต้องเห็น
    return user.role === Role.CUSTOMER ? { ...order, suggestion } : order;
  }

  /**
   * Server-Sent Events: แจ้งเมื่องานนี้เปลี่ยน (สถานะ ราคา ตำแหน่งช่าง) ให้แอปดึง GET /orders/:id ใหม่
   * ตรวจสิทธิ์ก่อนเปิด stream ผู้ที่ไม่เกี่ยวกับงานได้ 404 เหมือน GET ปกติ
   */
  @Sse(':id/events')
  @Roles(Role.CUSTOMER, Role.PROVIDER)
  @UseGuards(OrderAccessGuard)
  events(@Param('id') id: string): Observable<MessageEvent> {
    return this.orderEvents.stream(id);
  }

  @Post(':id/cancel')
  @Roles(Role.CUSTOMER)
  cancel(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.cancelByCustomer(user.sub, id);
  }

  @Patch(':id/en-route')
  @Roles(Role.PROVIDER)
  markEnRoute(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.updateStatusByProvider(
      user.sub,
      id,
      OrderStatus.EN_ROUTE,
    );
  }

  @Patch(':id/start')
  @Roles(Role.PROVIDER)
  markInProgress(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.updateStatusByProvider(
      user.sub,
      id,
      OrderStatus.IN_PROGRESS,
    );
  }

  @Post(':id/quote')
  @Roles(Role.PROVIDER)
  proposeQuote(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: ProposeQuoteDto,
  ) {
    return this.orders.proposeQuote(user.sub, id, dto);
  }

  @Post(':id/quote/approve')
  @Roles(Role.CUSTOMER)
  approveQuote(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: RespondQuoteDto,
  ) {
    return this.orders.respondToQuote(user.sub, id, true, dto);
  }

  @Post(':id/quote/reject')
  @Roles(Role.CUSTOMER)
  rejectQuote(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: RespondQuoteDto,
  ) {
    return this.orders.respondToQuote(user.sub, id, false, dto);
  }

  @Post(':id/complete')
  @Roles(Role.PROVIDER)
  complete(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.completeByProvider(user.sub, id);
  }

  @Post(':id/suggestion')
  @Roles(Role.CUSTOMER)
  suggest(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: ServiceSuggestionDto,
  ) {
    return this.orders.suggest(user.sub, id, dto);
  }

  @Post(':id/rate')
  @Roles(Role.CUSTOMER)
  rate(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: RateOrderDto,
  ) {
    return this.orders.rate(user.sub, id, dto);
  }
}
