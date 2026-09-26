import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Role } from '@prisma/client';

import { InspectionsService } from './inspections.service';
import { UpdateInspectionDto } from './dto/inspection.dto';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { JwtPayload } from '../auth/auth.service';

@Controller()
@UseGuards(JwtAuthGuard, RolesGuard)
export class InspectionsController {
  constructor(private readonly inspections: InspectionsService) {}

  /** แบบฟอร์มตรวจ 130+ จุด แอปดึงไปแสดงผล ไม่ต้อง hardcode ในแอป */
  @Get('inspections/checklist')
  @Roles(Role.CUSTOMER, Role.PROVIDER, Role.ADMIN)
  checklist() {
    return this.inspections.checklist();
  }

  @Get('orders/:id/inspection')
  @Roles(Role.CUSTOMER, Role.PROVIDER)
  get(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.inspections.getForActor(id, user);
  }

  @Patch('orders/:id/inspection')
  @Roles(Role.PROVIDER)
  update(
    @CurrentUser() user: JwtPayload,
    @Param('id') id: string,
    @Body() dto: UpdateInspectionDto,
  ) {
    return this.inspections.update(id, user.sub, dto);
  }

  @Post('orders/:id/inspection/submit')
  @Roles(Role.PROVIDER)
  submit(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.inspections.submit(id, user.sub);
  }
}
