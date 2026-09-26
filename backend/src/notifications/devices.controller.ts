import {
  Body,
  Controller,
  Delete,
  HttpCode,
  Post,
  UseGuards,
} from '@nestjs/common';
import { DevicePlatform, Role } from '@prisma/client';
import { IsEnum, IsString, MaxLength, MinLength } from 'class-validator';

import { JwtPayload } from '../auth/auth.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { PushService } from './push.service';

export class RegisterDeviceDto {
  @IsString()
  @MinLength(20)
  @MaxLength(4096)
  token!: string;

  @IsEnum(DevicePlatform)
  platform!: DevicePlatform;
}

export class UnregisterDeviceDto {
  @IsString()
  @MaxLength(4096)
  token!: string;
}

/** แอปลงทะเบียนโทเคน push หลังล็อกอิน และถอนออกตอนล็อกเอาต์ */
@Controller('devices')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.CUSTOMER, Role.PROVIDER)
export class DevicesController {
  constructor(private readonly push: PushService) {}

  @Post()
  @HttpCode(204)
  async register(
    @CurrentUser() user: JwtPayload,
    @Body() dto: RegisterDeviceDto,
  ): Promise<void> {
    // ช่างที่ยังไม่ส่งใบสมัครยังไม่มี id จริง รอให้สมัครเสร็จแล้วแอปจะลงทะเบียนใหม่
    if (user.sub.startsWith('pending:')) return;
    await this.push.registerDevice(
      user.sub,
      user.role,
      dto.token,
      dto.platform,
    );
  }

  @Delete()
  @HttpCode(204)
  async unregister(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UnregisterDeviceDto,
  ): Promise<void> {
    await this.push.unregisterDevice(user.sub, user.role, dto.token);
  }
}
