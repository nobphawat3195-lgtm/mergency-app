import { Body, Controller, Get, Patch, Post, UseGuards } from '@nestjs/common';
import { Role } from '@prisma/client';

import { ProvidersService } from './providers.service';
import {
  RegisterProviderDto,
  SetOnlineDto,
  UpdateLocationDto,
  UpdatePayoutInfoDto,
} from './dto/provider.dto';
import {
  CurrentUser,
  JwtAuthGuard,
  Roles,
  RolesGuard,
} from '../auth/guards';
import { AuthService, JwtPayload } from '../auth/auth.service';

@Controller('providers')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.PROVIDER)
export class ProvidersController {
  constructor(
    private readonly providers: ProvidersService,
    private readonly auth: AuthService,
  ) {}

  /** ยื่นใบสมัครเป็นช่าง — ใช้เบอร์จากโทเคน ไม่รับจาก body เพื่อกันการสมัครแทนคนอื่น */
  @Post('register')
  async register(
    @CurrentUser() user: JwtPayload,
    @Body() dto: RegisterProviderDto,
  ) {
    const provider = await this.providers.register(user.phone, dto);
    const session = await this.auth.issueProviderSession(user.phone);
    return { provider, ...session };
  }

  @Get('me')
  getMe(@CurrentUser() user: JwtPayload) {
    return this.providers.getMe(user.sub);
  }

  @Patch('me/online')
  setOnline(@CurrentUser() user: JwtPayload, @Body() dto: SetOnlineDto) {
    return this.providers.setOnline(user.sub, dto.isOnline);
  }

  @Patch('me/location')
  updateLocation(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateLocationDto,
  ) {
    return this.providers.updateLocation(user.sub, dto);
  }

  @Post('me/heartbeat')
  heartbeat(@CurrentUser() user: JwtPayload) {
    return this.providers.heartbeat(user.sub);
  }

  @Patch('me/payout-info')
  updatePayoutInfo(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdatePayoutInfoDto,
  ) {
    return this.providers.updatePayoutInfo(user.sub, dto);
  }
}
