import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { Role } from '@prisma/client';

import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';
import { OrderChatService } from './order-chat.service';
import {
  ReportOrderChatDto,
  SendOrderMessageDto,
} from './dto/order-chat.dto';

@Controller('orders/:id/messages')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.CUSTOMER, Role.PROVIDER)
export class OrderChatController {
  constructor(private readonly chat: OrderChatService) {}

  /** เปิดแชท: ข้อความทั้งหมด + ส่งต่อได้ไหม และนับว่าอ่านแล้ว */
  @Get()
  list(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.chat.list(id, user);
  }

  @Post()
  send(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: SendOrderMessageDto,
  ) {
    return this.chat.send(id, user, dto);
  }

  /** รายงานแชทไม่เหมาะสม ทีมงานได้แจ้งเตือนและเปิดอ่านแชทของงานนี้ได้ */
  @Post('report')
  report(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: ReportOrderChatDto,
  ) {
    return this.chat.report(id, user, dto.reason);
  }
}
