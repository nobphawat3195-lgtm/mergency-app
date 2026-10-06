import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import {
  IsBoolean,
  IsEnum,
  IsOptional,
  IsString,
  Length,
  Matches,
} from 'class-validator';
import {
  AdminRole,
  AdminUser,
  OrderStatus,
  ProviderStatus,
  Role,
  WithdrawalStatus,
} from '@prisma/client';

import { AdminService } from './admin.service';
import { FinanceService } from './finance.service';
import { PaymentsService } from '../payments/payments.service';
import { WalletService } from '../wallet/wallet.service';
import { JwtAuthGuard, Roles, RolesGuard } from '../auth/guards';
import {
  AdminAccessGuard,
  AdminAuditInterceptor,
  AdminAuditService,
  Audit,
  CurrentAdmin,
  OwnerOnly,
} from './admin-access';

export class AdminLoginDto {
  @Matches(/^0[0-9]{8,9}$/)
  phone!: string;

  @IsString()
  password!: string;
}

export class SetProviderStatusDto {
  @IsEnum(ProviderStatus)
  status!: ProviderStatus;

  /** เหตุผลที่ช่างเห็นในแอป บังคับเมื่อปฏิเสธ (REJECTED) หรือระงับ (SUSPENDED) */
  @IsOptional()
  @IsString()
  @Length(3, 300)
  note?: string;
}

export class SetActiveDto {
  @IsBoolean()
  active!: boolean;
}

export class CancelOrderDto {
  /** ข้อความนี้ส่งถึงลูกค้าทาง push เขียนให้ลูกค้าอ่านเข้าใจ */
  @IsString()
  @Length(5, 300)
  reason!: string;
}

export class ResolveWithdrawalDto {
  @IsOptional()
  @IsString()
  slipUrl?: string;

  @IsOptional()
  @IsString()
  note?: string;
}

export class CreateAdminDto {
  @Matches(/^0[0-9]{8,9}$/, { message: 'เบอร์โทรศัพท์ไม่ถูกต้อง' })
  phone!: string;

  @IsString()
  @Length(1, 60)
  name!: string;

  /** อย่างน้อย 12 ตัว เท่ากับที่ install.sh บังคับ */
  @IsString()
  @Length(12, 128, { message: 'รหัสผ่านต้องยาว 12 ตัวขึ้นไป' })
  password!: string;

  @IsEnum(AdminRole)
  role!: AdminRole;
}

export class UpdateAdminDto {
  @IsOptional()
  @IsEnum(AdminRole)
  role?: AdminRole;

  /** true = ปิดบัญชี, false = เปิดใช้อีกครั้ง */
  @IsOptional()
  @IsBoolean()
  disabled?: boolean;

  @IsOptional()
  @IsString()
  @Length(12, 128, { message: 'รหัสผ่านต้องยาว 12 ตัวขึ้นไป' })
  password?: string;
}

/** เข้าสู่ระบบหน้าแอดมิน (ไม่ต้องมีโทเคน) */
@Controller('admin')
export class AdminAuthController {
  constructor(private readonly admin: AdminService) {}

  @Post('login')
  login(@Body() dto: AdminLoginDto) {
    return this.admin.login(dto.phone, dto.password);
  }
}

/**
 * ทุก endpoint ต้องเป็นแอดมินที่ยังใช้งานได้ (ตรวจจากฐานข้อมูลทุกคำขอ)
 * @OwnerOnly = เจ้าของเท่านั้น (เงินเข้าออก รายงานการเงิน จัดการทีมงาน บันทึกการทำงาน)
 * @Audit = บันทึกว่าใครทำ เมื่อทำสำเร็จ
 */
@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard, AdminAccessGuard)
@Roles(Role.ADMIN)
@UseInterceptors(AdminAuditInterceptor)
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly payments: PaymentsService,
    private readonly wallet: WalletService,
    private readonly finance: FinanceService,
    private readonly audit: AdminAuditService,
  ) {}

  /** ข้อมูลของแอดมินที่ล็อกอินอยู่ หน้าแอดมินใช้ซ่อนส่วนที่ไม่มีสิทธิ์ */
  @Get('me')
  me(@CurrentAdmin() admin: AdminUser) {
    return {
      id: admin.id,
      name: admin.name,
      phone: admin.phone,
      role: admin.role,
    };
  }

  /** ทีมงานเห็นงานค้าง แต่ไม่เห็นตัวเลขรายได้ของเจ้าของ */
  @Get('summary')
  async summary(@CurrentAdmin() admin: AdminUser) {
    const summary = await this.admin.summary();
    if (admin.role === AdminRole.OWNER) return summary;
    const { commissionRevenue, outstandingDebt, ...operational } = summary;
    void commissionRevenue;
    void outstandingDebt;
    return operational;
  }

  // ---------- ช่าง ----------

  @Get('providers')
  listProviders(@Query('status') status?: ProviderStatus) {
    return this.admin.listProviders(status);
  }

  @Patch('providers/:id/status')
  @Audit('PROVIDER_STATUS', 'provider')
  setProviderStatus(
    @Param('id') id: string,
    @Body() dto: SetProviderStatusDto,
  ) {
    return this.admin.setProviderStatus(id, dto.status, dto.note);
  }

  // ---------- หมวดบริการ (เปิด/ปิดหมวดที่ยังไม่มีช่าง) ----------

  @Get('catalog')
  listCatalog() {
    return this.admin.listCatalog();
  }

  @Patch('catalog/categories/:id')
  @Audit('CATEGORY_ACTIVE', 'serviceCategory')
  setCategoryActive(@Param('id') id: string, @Body() dto: SetActiveDto) {
    return this.admin.setCategoryActive(id, dto.active);
  }

  @Patch('catalog/sub-services/:id')
  @Audit('SUB_SERVICE_ACTIVE', 'subService')
  setSubServiceActive(@Param('id') id: string, @Body() dto: SetActiveDto) {
    return this.admin.setSubServiceActive(id, dto.active);
  }

  // ---------- งาน ----------

  @Get('orders')
  listOrders(@Query('status') status?: OrderStatus) {
    return this.admin.listOrders(status);
  }

  @Post('orders/:id/redispatch')
  @Audit('ORDER_REDISPATCH', 'order')
  redispatch(@Param('id') id: string) {
    return this.admin.redispatchOrder(id);
  }

  @Post('orders/:id/cancel')
  @Audit('ORDER_CANCEL', 'order')
  cancelOrder(@Param('id') id: string, @Body() dto: CancelOrderDto) {
    return this.admin.cancelOrder(id, dto.reason);
  }

  // ---------- เงินเข้า: สลิปลูกค้า (ทีมงานดูได้ เจ้าของเป็นคนยืนยัน) ----------

  @Get('payments/slips')
  listSlips() {
    return this.payments.listSlipsForReview();
  }

  @Post('payments/:id/confirm')
  @OwnerOnly()
  @Audit('PAYMENT_CONFIRM', 'payment')
  confirmSlip(@Param('id') id: string) {
    return this.payments.confirmSlip(id);
  }

  @Post('payments/:id/reject')
  @OwnerOnly()
  @Audit('PAYMENT_REJECT', 'payment')
  rejectSlip(@Param('id') id: string, @Body() dto: CancelOrderDto) {
    return this.payments.rejectSlip(id, dto.reason);
  }

  /**
   * รายงานการเงินของเจ้าของ: ยอดรวม แยกพร้อมเพย์/เงินสด ค่าคอม และรายช่าง
   * ?from=YYYY-MM-DD&to=YYYY-MM-DD (เวลาไทย) ไม่ใส่ = เดือนนี้
   */
  @Get('finance')
  @OwnerOnly()
  financeReport(@Query('from') from?: string, @Query('to') to?: string) {
    return this.finance.report(from, to);
  }

  // ---------- ค่าคอมที่ช่างโอนคืน (งานเงินสด) ----------

  @Get('settlements')
  listSettlements() {
    return this.wallet.listSettlementsForReview();
  }

  @Post('settlements/:id/confirm')
  @OwnerOnly()
  @Audit('SETTLEMENT_CONFIRM', 'settlement')
  confirmSettlement(@Param('id') id: string) {
    return this.wallet.confirmSettlement(id);
  }

  @Post('settlements/:id/reject')
  @OwnerOnly()
  @Audit('SETTLEMENT_REJECT', 'settlement')
  rejectSettlement(@Param('id') id: string, @Body() dto: CancelOrderDto) {
    return this.wallet.rejectSettlement(id, dto.reason);
  }

  // ---------- เงินออก: ช่างขอเบิก ----------

  @Get('withdrawals')
  listWithdrawals(@Query('status') status?: WithdrawalStatus) {
    return this.admin.listWithdrawals(status);
  }

  @Post('withdrawals/:id/transferred')
  @OwnerOnly()
  @Audit('WITHDRAWAL_TRANSFERRED', 'withdrawal')
  markTransferred(@Param('id') id: string, @Body() dto: ResolveWithdrawalDto) {
    return this.admin.markWithdrawalTransferred(id, dto.slipUrl, dto.note);
  }

  @Post('withdrawals/:id/reject')
  @OwnerOnly()
  @Audit('WITHDRAWAL_REJECT', 'withdrawal')
  reject(@Param('id') id: string, @Body() dto: ResolveWithdrawalDto) {
    return this.admin.rejectWithdrawal(id, dto.note);
  }

  // ---------- ทีมงานและบันทึกการทำงาน (เจ้าของ) ----------

  @Get('admins')
  @OwnerOnly()
  listAdmins() {
    return this.admin.listAdmins();
  }

  @Post('admins')
  @OwnerOnly()
  async createAdmin(
    @CurrentAdmin() owner: AdminUser,
    @Body() dto: CreateAdminDto,
  ) {
    const created = await this.admin.createAdmin(dto);
    await this.audit.record(
      owner,
      'ADMIN_CREATE',
      { type: 'admin', id: created.id },
      { name: created.name, role: created.role },
    );
    return created;
  }

  @Patch('admins/:id')
  @OwnerOnly()
  @Audit('ADMIN_UPDATE', 'admin')
  updateAdmin(
    @CurrentAdmin() owner: AdminUser,
    @Param('id') id: string,
    @Body() dto: UpdateAdminDto,
  ) {
    return this.admin.updateAdmin(owner.id, id, dto);
  }

  @Get('audit')
  @OwnerOnly()
  listAudit(@Query('limit') limit?: string) {
    return this.audit.list(limit ? Number(limit) || 200 : 200);
  }
}
