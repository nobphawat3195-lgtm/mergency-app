import { Injectable, Logger } from '@nestjs/common';
import { createPrivateKey, sign as cryptoSign } from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';

const APPLE_AUDIENCE = 'https://appleid.apple.com';
const TOKEN_URL = 'https://appleid.apple.com/auth/token';
const REVOKE_URL = 'https://appleid.apple.com/auth/revoke';

/**
 * refresh token ของ Sign in with Apple: เก็บตอนล็อกอิน และ revoke ตอนลบบัญชี
 * (App Store Guideline 5.1.1(v) บังคับให้ยกเลิกสิทธิ์กับ Apple เมื่อผู้ใช้ลบบัญชี)
 *
 * ต้องมี key ของ Sign in with Apple จาก Apple Developer > Keys:
 * APPLE_TEAM_ID, APPLE_SIGNIN_KEY_ID, APPLE_SIGNIN_PRIVATE_KEY (เนื้อไฟล์ .p8, ขึ้นบรรทัดด้วย \n)
 * ไม่ตั้งค่า = ไม่เก็บและไม่ revoke ล็อกอินและลบบัญชียังทำงานปกติ
 *
 * อยู่ใน AccountModule (global) เพราะทั้งล็อกอิน (AuthModule) และลบบัญชีใช้
 */
@Injectable()
export class AppleTokenService {
  private readonly logger = new Logger(AppleTokenService.name);

  constructor(private readonly prisma: PrismaService) {}

  private config() {
    const teamId = process.env.APPLE_TEAM_ID?.trim();
    const keyId = process.env.APPLE_SIGNIN_KEY_ID?.trim();
    const privateKey = process.env.APPLE_SIGNIN_PRIVATE_KEY?.trim().replace(
      /\\n/g,
      '\n',
    );
    if (!teamId || !keyId || !privateKey) return null;
    return { teamId, keyId, privateKey };
  }

  isEnabled(): boolean {
    return this.config() !== null;
  }

  /** client_secret ของ Apple: JWT ES256 ที่เซ็นด้วย key .p8 อายุ 5 นาที */
  clientSecret(clientId: string, now: number = Date.now()): string {
    const config = this.config();
    if (!config) throw new Error('ยังไม่ได้ตั้งค่า key ของ Sign in with Apple');
    const iat = Math.floor(now / 1000);
    const header = Buffer.from(
      JSON.stringify({ alg: 'ES256', kid: config.keyId }),
    ).toString('base64url');
    const claims = Buffer.from(
      JSON.stringify({
        iss: config.teamId,
        iat,
        exp: iat + 300,
        aud: APPLE_AUDIENCE,
        sub: clientId,
      }),
    ).toString('base64url');
    const signature = cryptoSign('sha256', Buffer.from(`${header}.${claims}`), {
      key: createPrivateKey(config.privateKey),
      dsaEncoding: 'ieee-p1363',
    }).toString('base64url');
    return `${header}.${claims}.${signature}`;
  }

  /** แลก authorization code (ใช้ได้ครั้งเดียว 5 นาที) เป็น refresh token แล้วเก็บไว้ */
  async store(
    appleUserId: string,
    clientId: string,
    authorizationCode: string,
  ): Promise<void> {
    if (!this.isEnabled()) return;
    const response = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: this.clientSecret(clientId),
        code: authorizationCode,
        grant_type: 'authorization_code',
      }),
    });
    if (!response.ok) throw new Error(`token ${response.status}`);
    const { refresh_token: refreshToken } = (await response.json()) as {
      refresh_token?: string;
    };
    if (!refreshToken) throw new Error('Apple ไม่ส่ง refresh_token');
    await this.prisma.appleToken.upsert({
      where: { appleUserId },
      create: { appleUserId, clientId, refreshToken },
      update: { clientId, refreshToken },
    });
  }

  /**
   * ยกเลิกสิทธิ์ที่ผู้ใช้ให้แอปกับ Apple ห้าม throw: การลบบัญชีต้องสำเร็จเสมอ
   * ไม่มี token (ล็อกอินก่อนตั้งค่า key) ข้ามไป ผู้ใช้ถอนเองได้ที่ การตั้งค่า > Apple ID
   */
  async revoke(appleUserId: string): Promise<void> {
    const stored = await this.prisma.appleToken
      .findUnique({ where: { appleUserId } })
      .catch(() => null);
    if (!stored) return;
    try {
      if (this.isEnabled()) {
        const response = await fetch(REVOKE_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            client_id: stored.clientId,
            client_secret: this.clientSecret(stored.clientId),
            token: stored.refreshToken,
            token_type_hint: 'refresh_token',
          }),
        });
        if (!response.ok) {
          this.logger.warn(
            `revoke token ของ Apple ไม่สำเร็จ: ${response.status}`,
          );
        }
      }
    } catch (error) {
      this.logger.warn(
        `revoke token ของ Apple ไม่สำเร็จ: ${error instanceof Error ? error.message : error}`,
      );
    } finally {
      await this.prisma.appleToken
        .delete({ where: { appleUserId } })
        .catch(() => undefined);
    }
  }
}
