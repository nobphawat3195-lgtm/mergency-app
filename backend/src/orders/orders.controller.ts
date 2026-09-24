import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { OrderStatus, Role } from '@prisma/client';

import { OrdersService } from './orders.service';
import { CreateOrderDto, ProposeQuoteDto, RateOrderDto } from './dto/order.dto';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';

@Controller('orders')
@UseGuards(JwtAuthGuard, RolesGuard)
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

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

  @Get(':id')
  @Roles(Role.CUSTOMER, Role.PROVIDER)
  findOne(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.findAccessibleById(id, user);
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
  approveQuote(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.respondToQuote(user.sub, id, true);
  }

  @Post(':id/quote/reject')
  @Roles(Role.CUSTOMER)
  rejectQuote(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.respondToQuote(user.sub, id, false);
  }

  @Post(':id/complete')
  @Roles(Role.PROVIDER)
  complete(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.orders.completeByProvider(user.sub, id);
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
