import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { map, Observable } from 'rxjs';

/** ฟิลด์ภายในที่ห้ามส่งให้แอปลูกค้า/ช่าง (อัตราค่าธรรมเนียมเป็นข้อมูลของบริษัท) */
const INTERNAL_FIELDS = new Set(['commissionRate']);

export function stripInternalFields(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stripInternalFields);
  if (value === null || typeof value !== 'object') return value;
  // Date, Buffer, Decimal ฯลฯ ส่งต่อตามเดิม เพื่อให้ JSON serialize เหมือนเดิม
  const proto = Object.getPrototypeOf(value) as object | null;
  if (proto !== Object.prototype && proto !== null) return value;
  const result: Record<string, unknown> = {};
  for (const [key, field] of Object.entries(value)) {
    if (INTERNAL_FIELDS.has(key)) continue;
    result[key] = stripInternalFields(field);
  }
  return result;
}

/** ตัดฟิลด์ภายในออกจากทุก response ยกเว้น API ของแอดมิน */
@Injectable()
export class HideInternalFieldsInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();
    const request = context.switchToHttp().getRequest<{ path?: string; url?: string }>();
    const path = request.path ?? request.url ?? '';
    if (/^\/api\/admin(\/|$)/.test(path)) return next.handle();
    return next.handle().pipe(map(stripInternalFields));
  }
}
