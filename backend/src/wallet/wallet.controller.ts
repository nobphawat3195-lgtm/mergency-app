import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { IsInt, IsString, Length, Min } from 'class-validator';
import { Role } from '@prisma/client';

import { WalletService } from './wallet.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';

export class RequestWithdrawalDto {
  /** จำนวนเงินหน่วยสตางค์ */
  @IsInt()
  @Min(1)
  amount!: number;
}

export class SubmitSettlementDto {
  @IsString()
  @Length(1, 500)
  slipUrl!: string;
}

@Controller('wallet')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.PROVIDER)
export class WalletController {
  constructor(private readonly wallet: WalletService) {}

  @Get('balance')
  async getBalance(@CurrentUser() user: JwtPayload) {
    return { balance: await this.wallet.getBalance(user.sub) };
  }

  /** ค่าบริการค้างจากงานเงินสด เพดาน และสถานะสลิปโอนคืน */
  @Get('debt')
  getDebt(@CurrentUser() user: JwtPayload) {
    return this.wallet.getDebtStatus(user.sub);
  }

  @Get('settlement-qr')
  settlementQr(@CurrentUser() user: JwtPayload) {
    return this.wallet.settlementQr(user.sub);
  }

  @Post('settlements')
  submitSettlement(
    @CurrentUser() user: JwtPayload,
    @Body() dto: SubmitSettlementDto,
  ) {
    return this.wallet.submitSettlement(user.sub, dto.slipUrl);
  }

  @Get('entries')
  listEntries(@CurrentUser() user: JwtPayload) {
    return this.wallet.listEntries(user.sub);
  }

  @Get('withdrawals')
  listWithdrawals(@CurrentUser() user: JwtPayload) {
    return this.wallet.listWithdrawals(user.sub);
  }

  @Post('withdrawals')
  requestWithdrawal(
    @CurrentUser() user: JwtPayload,
    @Body() dto: RequestWithdrawalDto,
  ) {
    return this.wallet.requestWithdrawal(user.sub, dto.amount);
  }
}
