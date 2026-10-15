import { Injectable, Logger } from '@nestjs/common';
import { Role } from '@prisma/client';
import * as webpush from 'web-push';

import { PrismaService } from '../prisma/prisma.service';

export interface WebPushConfig {
  enabled: boolean;
  publicKey?: string;
  privateKey?: string;
  /** mailto: หรือ https: ของเจ้าของระบบ ผู้ให้บริการ push ใช้ติดต่อเมื่อมีปัญหา */
  subject?: string;
}

export function readWebPushConfig(
  env: NodeJS.ProcessEnv = process.env,
): WebPushConfig {
  const publicKey = env.VAPID_PUBLIC_KEY?.trim() || undefined;
  const privateKey = env.VAPID_PRIVATE_KEY?.trim() || undefined;
  const subject = env.VAPID_SUBJECT?.trim() || undefined;
  return {
    enabled:
      env.WEB_PUSH_ENABLED?.trim().toLowerCase() === 'true' &&
      Boolean(publicKey && privateKey && subject),
    publicKey,
    privateKey,
    subject,
  };
}

export interface WebPushTarget {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

export interface WebPushOptions {
  /** วินาทีที่ผู้ให้บริการ push เก็บข้อความไว้ถ้าเครื่องยังไม่ออนไลน์ (งานใหม่ = เวลาที่เหลือให้กดรับ) */
  TTL: number;
  urgency: 'normal' | 'high';
  /** ข้อความใหม่ topic เดียวกันแทนข้อความเก่าที่ยังส่งไม่ถึง */
  topic?: string;
}

/** แยกจาก web-push เพื่อให้เทสต์ส่งปลอมได้ คืน HTTP status ของผู้ให้บริการ push */
export type WebPushSender = (
  target: WebPushTarget,
  payload: string,
  options: WebPushOptions,
) => Promise<number>;

export function createWebPushSender(config: WebPushConfig): WebPushSender {
  return async (target, payload, options) => {
    try {
      const result = await webpush.sendNotification(target, payload, {
        TTL: options.TTL,
        urgency: options.urgency,
        topic: options.topic,
        vapidDetails: {
          subject: config.subject!,
          publicKey: config.publicKey!,
          privateKey: config.privateKey!,
        },
      });
      return result.statusCode;
    } catch (error) {
      // web-push throw WebPushError พร้อม statusCode เมื่อผู้ให้บริการตอบ 4xx/5xx
      const statusCode = (error as { statusCode?: number }).statusCode;
      if (typeof statusCode === 'number') return statusCode;
      throw error;
    }
  };
}

export interface WebPushMessage {
  title: string;
  body: string;
  type: string;
  orderId: string;
  orderNo: string;
}

/**
 * Web Push ไปยังเว็บแอปที่ติดตั้งลงหน้าจอหลัก ส่งคู่กับ FCM และ LINE
 *
 * ทุกเมธอดไม่ throw: เป็นช่องทางเสริม ห้ามทำให้การเสนองาน/ยกเลิกงานล้มเหลว
 * subscription ที่ผู้ให้บริการตอบ 404/410 (ถอนแอป ปิดการแจ้งเตือน) ถูกลบทิ้งเอง
 */
@Injectable()
export class WebPushService {
  private readonly logger = new Logger(WebPushService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: WebPushConfig = readWebPushConfig(),
    private readonly sender: WebPushSender = createWebPushSender(config),
  ) {
    if (
      !config.enabled &&
      process.env.WEB_PUSH_ENABLED?.trim().toLowerCase() === 'true'
    ) {
      this.logger.warn(
        'WEB_PUSH_ENABLED=true แต่ตั้ง VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT ไม่ครบ ปิด Web Push ไว้',
      );
    }
  }

  get enabled(): boolean {
    return this.config.enabled;
  }

  /** แอปใช้ public key นี้สมัคร push (ไม่ใช่ความลับ) */
  publicConfig(): { enabled: boolean; publicKey: string | null } {
    return {
      enabled: this.config.enabled,
      publicKey: this.config.enabled ? this.config.publicKey! : null,
    };
  }

  async subscribe(
    userId: string,
    role: Role,
    target: WebPushTarget,
  ): Promise<void> {
    const data = {
      p256dh: target.keys.p256dh,
      auth: target.keys.auth,
      role,
      userId,
      lastSeenAt: new Date(),
    };
    await this.prisma.webPushSubscription.upsert({
      where: { endpoint: target.endpoint },
      create: { endpoint: target.endpoint, ...data },
      update: data,
    });
  }

  async unsubscribe(userId: string, role: Role, endpoint: string) {
    await this.prisma.webPushSubscription.deleteMany({
      where: { endpoint, role, userId },
    });
  }

  async removeAll(userId: string, role: Role) {
    await this.prisma.webPushSubscription.deleteMany({
      where: { role, userId },
    });
  }

  async send(
    role: Role,
    userIds: string[],
    message: WebPushMessage,
    { ttlSeconds = 3600, urgent = false } = {},
  ): Promise<void> {
    if (!this.config.enabled || userIds.length === 0) return;
    try {
      const subscriptions = await this.prisma.webPushSubscription.findMany({
        where: { role, userId: { in: userIds } },
        select: { endpoint: true, p256dh: true, auth: true },
      });
      const payload = JSON.stringify(message);
      // topic ยาวได้ไม่เกิน 32 ตัว (base64url) uuid ตัดขีดออกแล้วพอดี
      const topic = message.orderId
        ? message.orderId.replace(/-/g, '').slice(0, 32)
        : undefined;
      const gone: string[] = [];
      await Promise.all(
        subscriptions.map(async ({ endpoint, p256dh, auth }) => {
          try {
            const status = await this.sender(
              { endpoint, keys: { p256dh, auth } },
              payload,
              {
                TTL: Math.max(0, Math.round(ttlSeconds)),
                urgency: urgent ? 'high' : 'normal',
                topic,
              },
            );
            if (status === 404 || status === 410) gone.push(endpoint);
            else if (status >= 400) {
              this.logger.warn(`Web Push ไม่สำเร็จ HTTP ${status}`);
            }
          } catch (error) {
            this.logger.warn(`Web Push ไม่สำเร็จ: ${(error as Error).message}`);
          }
        }),
      );
      if (gone.length > 0) {
        await this.prisma.webPushSubscription.deleteMany({
          where: { endpoint: { in: gone } },
        });
      }
    } catch (error) {
      this.logger.warn(
        `Web Push ${message.type} ล้มเหลว: ${(error as Error).message}`,
      );
    }
  }
}
