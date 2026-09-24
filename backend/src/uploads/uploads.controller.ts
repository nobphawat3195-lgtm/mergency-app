import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { Role } from '@prisma/client';

import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';
import { PresignUploadDto } from './dto/presign-upload.dto';
import { UploadsService } from './uploads.service';

@Controller('uploads')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.CUSTOMER, Role.PROVIDER)
export class UploadsController {
  constructor(private readonly uploads: UploadsService) {}

  @Post('presign')
  presign(
    @CurrentUser() user: JwtPayload,
    @Body() dto: PresignUploadDto,
  ) {
    return this.uploads.createPresignedUpload(user.sub, user.role, dto);
  }
}
