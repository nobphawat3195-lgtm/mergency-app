import { Controller, Get, Header, Param } from '@nestjs/common';

import { OrderShareService } from './order-share.service';

/** หน้าติดตามงานที่ลูกค้าแชร์ให้ครอบครัว เปิดได้โดยไม่ต้องล็อกอิน (โทเคนคือสิทธิ์) */
@Controller('public/track')
export class PublicTrackingController {
  constructor(private readonly share: OrderShareService) {}

  @Get(':token')
  @Header('Cache-Control', 'no-store')
  @Header('Referrer-Policy', 'no-referrer')
  view(@Param('token') token: string) {
    return this.share.view(token);
  }
}
