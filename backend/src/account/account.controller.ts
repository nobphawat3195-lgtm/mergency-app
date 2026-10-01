import { Controller, Delete, Get, UseGuards } from '@nestjs/common';
import { Role } from '@prisma/client';

import { JwtPayload } from '../auth/auth.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { AccountService } from './account.service';

@Controller('account')
@UseGuards(JwtAuthGuard, RolesGuard)
export class AccountController {
  constructor(private readonly account: AccountService) {}

  /** ชื่อและเบอร์ของลูกค้าที่ล็อกอินอยู่ ให้หน้าโปรไฟล์แสดงว่าเข้าบัญชีไหน */
  @Get()
  @Roles(Role.CUSTOMER)
  profile(@CurrentUser() user: JwtPayload) {
    return this.account.customerProfile(user.sub);
  }

  @Delete()
  @Roles(Role.CUSTOMER, Role.PROVIDER)
  delete(@CurrentUser() user: JwtPayload) {
    return this.account.deleteAccount(user.sub, user.role);
  }
}
