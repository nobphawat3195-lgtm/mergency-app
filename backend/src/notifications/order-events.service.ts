import { Injectable, MessageEvent } from '@nestjs/common';
import { filter, interval, map, merge, Observable, Subject } from 'rxjs';

export interface OrderEvent {
  orderId: string;
  /** เหตุการณ์แบบเดียวกับ push type หรือ LOCATION เมื่อช่างขยับ */
  type: string;
}

/** ส่ง ping ทุก 25 วินาที กัน proxy/มือถือตัดการเชื่อมต่อที่เงียบนาน */
const KEEPALIVE_MS = 25_000;

/**
 * สัญญาณว่างานเปลี่ยน ให้แอปที่เปิดหน้าติดตามงานดึงข้อมูลใหม่ทันที (Server-Sent Events)
 *
 * ส่งแค่ประเภทเหตุการณ์ ไม่ส่งข้อมูลงาน แอปต้องเรียก GET /orders/:id ซึ่งตรวจสิทธิ์ทุกครั้ง
 * อยู่ในหน่วยความจำของ process เดียว ถ้าขยายเป็นหลายเครื่องต้องเปลี่ยนเป็น Redis pub/sub
 */
@Injectable()
export class OrderEventsService {
  private readonly events = new Subject<OrderEvent>();

  emit(orderId: string, type: string): void {
    this.events.next({ orderId, type });
  }

  stream(orderId: string): Observable<MessageEvent> {
    const changes = this.events.pipe(
      filter((event) => event.orderId === orderId),
      map(
        (event): MessageEvent => ({
          type: 'order',
          data: { type: event.type },
        }),
      ),
    );
    const keepalive = interval(KEEPALIVE_MS).pipe(
      map((): MessageEvent => ({ type: 'ping', data: {} })),
    );
    return merge(changes, keepalive);
  }
}
