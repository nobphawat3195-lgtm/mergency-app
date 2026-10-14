import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Role } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsString, IsUrl, MaxLength, ValidateNested } from 'class-validator';

import { JwtPayload } from '../auth/auth.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { WebPushService } from './web-push.service';

class WebPushKeysDto {
  @IsString()
  @MaxLength(200)
  p256dh!: string;

  @IsString()
  @MaxLength(100)
  auth!: string;
}

export class WebPushSubscriptionDto {
  @IsUrl({ protocols: ['https'], require_protocol: true })
  @MaxLength(1000)
  endpoint!: string;

  @ValidateNested()
  @Type(() => WebPushKeysDto)
  keys!: WebPushKeysDto;
}

export class RemoveWebPushDto {
  @IsString()
  @MaxLength(1000)
  endpoint!: string;
}

/** เว็บแอปช่างที่ติดตั้งลงหน้าจอหลักสมัคร Web Push หลังช่างกดอนุญาตแจ้งเตือน */
@Controller('web-push')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.PROVIDER)
export class WebPushController {
  constructor(private readonly webPush: WebPushService) {}

  @Get('config')
  config() {
    return this.webPush.publicConfig();
  }

  @Post('subscriptions')
  @HttpCode(204)
  async subscribe(
    @CurrentUser() user: JwtPayload,
    @Body() dto: WebPushSubscriptionDto,
  ): Promise<void> {
    // ช่างที่ยังไม่ส่งใบสมัครยังไม่มี id จริง แอปจะสมัครใหม่หลังสมัครเสร็จ
    if (user.sub.startsWith('pending:') || !this.webPush.enabled) return;
    await this.webPush.subscribe(user.sub, user.role, dto);
  }

  @Delete('subscriptions')
  @HttpCode(204)
  async unsubscribe(
    @CurrentUser() user: JwtPayload,
    @Body() dto: RemoveWebPushDto,
  ): Promise<void> {
    await this.webPush.unsubscribe(user.sub, user.role, dto.endpoint);
  }
}
