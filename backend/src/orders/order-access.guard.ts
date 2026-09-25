import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';

import { JwtPayload } from '../auth/auth.service';
import { OrdersService } from './orders.service';

/**
 * ตรวจว่าผู้เรียกเป็นลูกค้าหรือช่างของงาน :id ก่อนเข้า handler
 *
 * ใช้กับ @Sse เพราะ Nest ส่ง header 200 ของ event-stream ทันทีที่ handler เริ่ม
 * ถ้าตรวจสิทธิ์ใน handler คนนอกจะได้ 200 แล้วค่อยได้ event error แทนที่จะเป็น 404
 */
@Injectable()
export class OrderAccessGuard implements CanActivate {
  constructor(private readonly orders: OrdersService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest<{ user: JwtPayload; params: { id: string } }>();
    // throw NotFoundException ถ้าไม่มีสิทธิ์ (ไม่บอกว่างานนี้มีอยู่จริงหรือไม่)
    await this.orders.findAccessibleById(request.params.id, request.user);
    return true;
  }
}
