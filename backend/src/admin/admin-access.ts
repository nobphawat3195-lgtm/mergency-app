import {
  CallHandler,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Logger,
  NestInterceptor,
  SetMetadata,
  UnauthorizedException,
  createParamDecorator,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AdminRole, AdminUser, Prisma } from '@prisma/client';
import { Observable, tap } from 'rxjs';

import { PrismaService } from '../prisma/prisma.service';
import { JwtPayload } from '../auth/auth.service';

const OWNER_ONLY = 'admin:owner-only';
const AUDIT = 'admin:audit';

/** เฉพาะเจ้าของ: เรื่องเงินเข้าออกและการจัดการทีมงาน */
export const OwnerOnly = () => SetMetadata(OWNER_ONLY, true);

/**
 * บันทึกการกระทำนี้ลง audit log เมื่อทำสำเร็จ
 * targetType = ชนิดของ :id ใน path เช่น 'provider', 'payment'
 */
export const Audit = (action: string, targetType?: string) =>
  SetMetadata(AUDIT, { action, targetType });

type AdminRequest = {
  user?: JwtPayload;
  admin?: AdminUser;
  params?: Record<string, string>;
  body?: Record<string, unknown>;
};

/** แอดมินที่ผ่าน AdminAccessGuard แล้ว (อ่านจากฐานข้อมูลทุกคำขอ ไม่เชื่อสิทธิ์ในโทเคน) */
export const CurrentAdmin = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AdminUser =>
    ctx.switchToHttp().getRequest<AdminRequest>().admin as AdminUser,
);

/**
 * ตรวจว่าบัญชีแอดมินยังใช้งานได้ และมีสิทธิ์ตามที่ endpoint ต้องการ
 * อ่านบทบาทจากฐานข้อมูลทุกครั้ง: ปิดบัญชีหรือลดสิทธิ์แล้วมีผลทันทีแม้โทเคนยังไม่หมดอายุ
 */
@Injectable()
export class AdminAccessGuard implements CanActivate {
  constructor(
    private readonly prisma: PrismaService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AdminRequest>();
    const sub = request.user?.sub;
    if (!sub) throw new UnauthorizedException();
    const admin = await this.prisma.adminUser.findUnique({
      where: { id: sub },
    });
    if (!admin || admin.disabledAt) {
      throw new UnauthorizedException('บัญชีแอดมินนี้ถูกปิดแล้ว');
    }
    const ownerOnly = this.reflector.getAllAndOverride<boolean | undefined>(
      OWNER_ONLY,
      [context.getHandler(), context.getClass()],
    );
    if (ownerOnly && admin.role !== AdminRole.OWNER) {
      throw new ForbiddenException('ส่วนนี้สำหรับเจ้าของเท่านั้น');
    }
    request.admin = admin;
    return true;
  }
}

/** ฟิลด์จาก body ที่ปลอดภัยพอจะเก็บในบันทึก (ไม่มีรหัสผ่าน) */
const DETAIL_FIELDS = ['status', 'note', 'reason', 'role', 'disabled'];

@Injectable()
export class AdminAuditService {
  private readonly logger = new Logger(AdminAuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  async record(
    admin: Pick<AdminUser, 'id' | 'name'>,
    action: string,
    target?: { type?: string; id?: string },
    detail?: Record<string, unknown>,
  ): Promise<void> {
    try {
      await this.prisma.adminAuditLog.create({
        data: {
          adminId: admin.id,
          adminName: admin.name,
          action,
          targetType: target?.type ?? null,
          targetId: target?.id ?? null,
          detail:
            detail && Object.keys(detail).length > 0
              ? (detail as Prisma.InputJsonValue)
              : Prisma.DbNull,
        },
      });
    } catch (error) {
      // บันทึกไม่สำเร็จต้องไม่ทำให้งานที่ทำสำเร็จแล้วกลายเป็น error
      this.logger.error(`บันทึก audit ไม่สำเร็จ: ${action}`, error as Error);
    }
  }

  list(limit = 200) {
    return this.prisma.adminAuditLog.findMany({
      orderBy: { createdAt: 'desc' },
      take: Math.min(Math.max(limit, 1), 500),
    });
  }
}

/** บันทึก endpoint ที่ติด @Audit หลังทำสำเร็จ */
@Injectable()
export class AdminAuditInterceptor implements NestInterceptor {
  constructor(
    private readonly reflector: Reflector,
    private readonly audit: AdminAuditService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const meta = this.reflector.get<
      { action: string; targetType?: string } | undefined
    >(AUDIT, context.getHandler());
    if (!meta) return next.handle();
    const request = context.switchToHttp().getRequest<AdminRequest>();
    return next.handle().pipe(
      tap(() => {
        const admin = request.admin;
        if (!admin) return;
        const detail: Record<string, unknown> = {};
        for (const key of DETAIL_FIELDS) {
          const value = request.body?.[key];
          if (value !== undefined && value !== null && value !== '') {
            detail[key] = value;
          }
        }
        void this.audit.record(
          admin,
          meta.action,
          { type: meta.targetType, id: request.params?.id },
          detail,
        );
      }),
    );
  }
}
