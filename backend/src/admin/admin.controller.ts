import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { IsEnum, IsOptional, IsString, Length, Matches } from 'class-validator';
import {
  OrderStatus,
  ProviderStatus,
  Role,
  WithdrawalStatus,
} from '@prisma/client';

import { AdminService } from './admin.service';
import { PaymentsService } from '../payments/payments.service';
import { JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';

export class AdminLoginDto {
  @Matches(/^0[0-9]{8,9}$/)
  phone!: string;

  @IsString()
  password!: string;
}

export class SetProviderStatusDto {
  @IsEnum(ProviderStatus)
  status!: ProviderStatus;
}

export class CancelOrderDto {
  /** ข้อความนี้ส่งถึงลูกค้าทาง push เขียนให้ลูกค้าอ่านเข้าใจ */
  @IsString()
  @Length(5, 300)
  reason!: string;
}

export class ResolveWithdrawalDto {
  @IsOptional()
  @IsString()
  slipUrl?: string;

  @IsOptional()
  @IsString()
  note?: string;
}

@Controller('admin')
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly payments: PaymentsService,
  ) {}

  @Post('login')
  login(@Body() dto: AdminLoginDto) {
    return this.admin.login(dto.phone, dto.password);
  }

  @Get('summary')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  summary() {
    return this.admin.summary();
  }

  @Get('providers')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  listProviders(@Query('status') status?: ProviderStatus) {
    return this.admin.listProviders(status);
  }

  @Patch('providers/:id/status')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  setProviderStatus(
    @Param('id') id: string,
    @Body() dto: SetProviderStatusDto,
  ) {
    return this.admin.setProviderStatus(id, dto.status);
  }

  @Get('orders')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  listOrders(@Query('status') status?: OrderStatus) {
    return this.admin.listOrders(status);
  }

  @Post('orders/:id/redispatch')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  redispatch(@Param('id') id: string) {
    return this.admin.redispatchOrder(id);
  }

  @Post('orders/:id/cancel')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  cancelOrder(@Param('id') id: string, @Body() dto: CancelOrderDto) {
    return this.admin.cancelOrder(id, dto.reason);
  }

  @Get('payments/slips')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  listSlips() {
    return this.payments.listSlipsForReview();
  }

  @Post('payments/:id/confirm')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  confirmSlip(@Param('id') id: string) {
    return this.payments.confirmSlip(id);
  }

  @Post('payments/:id/reject')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  rejectSlip(@Param('id') id: string, @Body() dto: CancelOrderDto) {
    return this.payments.rejectSlip(id, dto.reason);
  }

  @Get('withdrawals')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  listWithdrawals(@Query('status') status?: WithdrawalStatus) {
    return this.admin.listWithdrawals(status);
  }

  @Post('withdrawals/:id/transferred')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  markTransferred(@Param('id') id: string, @Body() dto: ResolveWithdrawalDto) {
    return this.admin.markWithdrawalTransferred(id, dto.slipUrl, dto.note);
  }

  @Post('withdrawals/:id/reject')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  reject(@Param('id') id: string, @Body() dto: ResolveWithdrawalDto) {
    return this.admin.rejectWithdrawal(id, dto.note);
  }
}
