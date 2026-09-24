import { Controller, Delete, UseGuards } from '@nestjs/common';
import { Role } from '@prisma/client';

import { JwtPayload } from '../auth/auth.service';
import { CurrentUser, JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import { AccountService } from './account.service';

@Controller('account')
@UseGuards(JwtAuthGuard, RolesGuard)
export class AccountController {
  constructor(private readonly account: AccountService) {}

  @Delete()
  @Roles(Role.CUSTOMER, Role.PROVIDER)
  delete(@CurrentUser() user: JwtPayload) {
    return this.account.deleteAccount(user.sub, user.role);
  }
}
