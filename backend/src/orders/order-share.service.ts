import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrderStatus } from '@prisma/client';
import { randomBytes } from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';
import { publicWebUrl } from '../config/environment';
import { PROVIDER_CARD_SELECT, presentProviderCard } from './provider-card';

/** ลิงก์ของงานที่จบแล้วเปิดดูต่อได้อีกช่วงหนึ่ง ครอบครัวจะได้เห็นว่าเรียบร้อยแล้ว */
export const SHARE_GRACE_MS = 2 * 60 * 60_000;

/** โทเคนสุ่ม 32 ไบต์แบบ base64url (43 ตัวอักษร) เดาไม่ได้ */
export const SHARE_TOKEN = /^[A-Za-z0-9_-]{43}$/;

const FINISHED: OrderStatus[] = [OrderStatus.COMPLETED, OrderStatus.CANCELLED];

/**
 * ลิงก์ติดตามงานสำหรับครอบครัว/เพื่อน: เปิดได้โดยไม่ต้องล็อกอิน ดูได้อย่างเดียว
 * เห็นสถานะ จุดนัด และช่างที่กำลังมา แต่ไม่เห็นเบอร์โทร ราคา หรือข้อมูลการชำระเงิน
 */
@Injectable()
export class OrderShareService {
  constructor(private readonly prisma: PrismaService) {}

  private publicUrl(token: string): string | null {
    const base = publicWebUrl();
    return base ? `${base}/track/${token}` : null;
  }

  async share(orderId: string, customerId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { customerId: true, status: true, shareToken: true },
    });
    if (!order || order.customerId !== customerId) {
      throw new NotFoundException('ไม่พบออเดอร์นี้');
    }
    if (FINISHED.includes(order.status)) {
      throw new BadRequestException('งานนี้จบแล้ว ไม่ต้องแชร์ลิงก์ติดตาม');
    }
    let token = order.shareToken;
    if (!token) {
      token = randomBytes(32).toString('base64url');
      await this.prisma.order.update({
        where: { id: orderId },
        data: { shareToken: token },
      });
    }
    return { token, path: `/track/${token}`, url: this.publicUrl(token) };
  }

  async revoke(orderId: string, customerId: string) {
    const { count } = await this.prisma.order.updateMany({
      where: { id: orderId, customerId },
      data: { shareToken: null },
    });
    if (count === 0) throw new NotFoundException('ไม่พบออเดอร์นี้');
    return { revoked: true };
  }

  async view(token: string, now: number = Date.now()) {
    if (!SHARE_TOKEN.test(token))
      throw new NotFoundException('ลิงก์ไม่ถูกต้อง');
    const order = await this.prisma.order.findUnique({
      where: { shareToken: token },
      select: {
        status: true,
        pickupLat: true,
        pickupLng: true,
        createdAt: true,
        matchedAt: true,
        completedAt: true,
        cancelledAt: true,
        category: { select: { name: true } },
        subService: { select: { name: true } },
        provider: { select: PROVIDER_CARD_SELECT },
      },
    });
    if (!order) throw new NotFoundException('ลิงก์หมดอายุหรือถูกยกเลิกแล้ว');
    const finishedAt = order.completedAt ?? order.cancelledAt;
    if (
      FINISHED.includes(order.status) &&
      (!finishedAt || now - finishedAt.getTime() > SHARE_GRACE_MS)
    ) {
      throw new NotFoundException('ลิงก์หมดอายุหรือถูกยกเลิกแล้ว');
    }

    const card = order.provider
      ? presentProviderCard(order, order.provider, now)
      : null;
    return {
      status: order.status,
      categoryName: order.category.name,
      subServiceName: order.subService.name,
      pickup: { lat: order.pickupLat, lng: order.pickupLng },
      createdAt: order.createdAt,
      matchedAt: order.matchedAt,
      finishedAt,
      // ไม่ส่งเบอร์โทรและชื่อจริงของช่างออกไปกับลิงก์สาธารณะ
      provider: card && {
        nickname: card.nickname,
        photoUrl: card.photoUrl,
        verified: card.verified,
        ratingAvg: card.ratingAvg,
        ratingCount: card.ratingCount,
        completedJobs: card.completedJobs,
        vehicleDesc: card.vehicleDesc,
        vehiclePlate: card.vehiclePlate,
        currentLat: card.currentLat,
        currentLng: card.currentLng,
        locationUpdatedAt: card.locationUpdatedAt,
        distanceKm: card.distanceKm,
        etaMinutes: card.etaMinutes,
      },
    };
  }
}
