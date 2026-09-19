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
import { IsEnum, IsOptional, IsString, Matches } from 'class-validator';
import {
  OrderStatus,
  ProviderStatus,
  Role,
  WithdrawalStatus,
} from '@prisma/client';

import { AdminService } from './admin.service';
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
  constructor(private readonly admin: AdminService) {}

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

  @Get('withdrawals')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  listWithdrawals(@Query('status') status?: WithdrawalStatus) {
    return this.admin.listWithdrawals(status);
  }

  @Post('withdrawals/:id/transferred')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  markTransferred(
    @Param('id') id: string,
    @Body() dto: ResolveWithdrawalDto,
  ) {
    return this.admin.markWithdrawalTransferred(id, dto.slipUrl, dto.note);
  }

  @Post('withdrawals/:id/reject')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(Role.ADMIN)
  reject(@Param('id') id: string, @Body() dto: ResolveWithdrawalDto) {
    return this.admin.rejectWithdrawal(id, dto.note);
  }
}
