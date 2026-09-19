import { Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { Role } from '@prisma/client';

import { DispatchService } from './dispatch.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';

@Controller('dispatch')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.PROVIDER)
export class DispatchController {
  constructor(private readonly dispatch: DispatchService) {}

  /** งานที่กำลังเสนอให้ช่างคนนี้อยู่ */
  @Get('offers')
  listOffers(@CurrentUser() user: JwtPayload) {
    return this.dispatch.listOffersForProvider(user.sub);
  }

  @Post('offers/:orderId/accept')
  async accept(@CurrentUser() user: JwtPayload, @Param('orderId') orderId: string) {
    await this.dispatch.accept(orderId, user.sub);
    return { accepted: true };
  }

  @Post('offers/:orderId/reject')
  async reject(@CurrentUser() user: JwtPayload, @Param('orderId') orderId: string) {
    await this.dispatch.reject(orderId, user.sub);
    return { rejected: true };
  }
}
