import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { IsInt, Min } from 'class-validator';
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

@Controller('wallet')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.PROVIDER)
export class WalletController {
  constructor(private readonly wallet: WalletService) {}

  @Get('balance')
  async getBalance(@CurrentUser() user: JwtPayload) {
    return { balance: await this.wallet.getBalance(user.sub) };
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
