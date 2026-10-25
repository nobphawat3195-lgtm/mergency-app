import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import {
  createHash,
  createPublicKey,
  JsonWebKey,
  KeyObject,
  timingSafeEqual,
  verify as cryptoVerify,
} from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';
import { JwtPayload } from './auth.service';
import { AppleTokenService } from './apple-token.service';

export const APPLE_ISSUER = 'https://appleid.apple.com';
const KEYS_URL = 'https://appleid.apple.com/auth/keys';

/** public key ของ Apple เปลี่ยนไม่บ่อย เก็บไว้ 1 ชั่วโมง (kid ไม่รู้จักจะโหลดใหม่ทันที) */
const KEYS_TTL_MS = 60 * 60_000;
/** เผื่อเวลาเครื่องเซิร์ฟเวอร์กับ Apple ไม่ตรงกัน */
const CLOCK_SKEW_SECONDS = 60;

export type AppleApp = 'customer' | 'provider';

export function parseAppleApp(value: unknown): AppleApp {
  return value === 'provider' ? 'provider' : 'customer';
}

/** bundle id ของแอป iPhone = aud ใน identity token และ client_id ตอนแลก/ยกเลิก token */
export function appleClientId(
  app: AppleApp,
  env: NodeJS.ProcessEnv = process.env,
): string {
  const configured =
    app === 'provider'
      ? env.APPLE_PROVIDER_CLIENT_ID?.trim()
      : env.APPLE_CUSTOMER_CLIENT_ID?.trim();
  return (
    configured ||
    (app === 'provider' ? 'com.fixgo.fixgoProvider' : 'com.fixgo.fixgoCustomer')
  );
}

export interface AppleSignInInput {
  app: AppleApp;
  identityToken: string;
  /** nonce ดิบที่แอปสุ่ม แอปส่ง sha256 ของค่านี้ให้ Apple ใน identity token จึงมี hash */
  nonce: string;
  /** ใช้ครั้งเดียว 5 นาที แลกเป็น refresh token ไว้ revoke ตอนลบบัญชี */
  authorizationCode?: string;
  /** Apple ส่งชื่อให้เฉพาะครั้งแรกที่ผู้ใช้กดยอมรับ */
  fullName?: string;
}

interface AppleClaims {
  iss?: string;
  aud?: string;
  sub?: string;
  exp?: number;
  iat?: number;
  nonce?: string;
}

interface AppleJwk extends JsonWebKey {
  kid: string;
}

function decodeJson<T>(part: string): T {
  return JSON.parse(Buffer.from(part, 'base64url').toString('utf8')) as T;
}

function safeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}

/**
 * Sign in with Apple สำหรับแอป iPhone (App Store Guideline 4.8 เมื่อมี LINE Login)
 *
 * แอปได้ identity token (JWT ที่ Apple เซ็นด้วย RS256) มาจาก ASAuthorizationController
 * เซิร์ฟเวอร์ตรวจลายเซ็นกับ public key ของ Apple, iss, aud (= bundle id ของแอปนั้น), อายุ
 * และ nonce เอง ไม่ต้องตั้งค่าอะไร
 *
 * ลูกค้า: สร้าง/เข้าบัญชีด้วย appleUserId (Apple ไม่ส่งเบอร์โทร phone จึงเป็น null เหมือน LINE)
 * ช่าง: เข้าบัญชีเดิม หรือได้โทเคนชั่วคราว (sub = pending:apple:<id>) ไว้ส่งใบสมัคร
 *
 * refresh token ไว้ revoke ตอนลบบัญชีอยู่ใน AppleTokenService
 */
@Injectable()
export class AppleLoginService {
  private readonly logger = new Logger(AppleLoginService.name);
  private keys = new Map<string, KeyObject>();
  private keysLoadedAt = 0;
  /** identity token ที่ใช้ไปแล้ว (เก็บจนหมดอายุ) กันส่งซ้ำ */
  private readonly usedTokens = new Map<string, number>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly tokens: AppleTokenService,
  ) {}

  async signIn(input: AppleSignInInput, now: number = Date.now()) {
    const appleUserId = await this.verifyIdentityToken(
      input.identityToken,
      input.nonce,
      appleClientId(input.app),
      now,
    );
    if (input.authorizationCode) {
      // ไม่ให้ล็อกอินล้มเพราะแลก token ไม่ได้ ผู้ใช้เข้าได้ แค่ยังไม่มี token ไว้ revoke
      await this.tokens
        .store(appleUserId, appleClientId(input.app), input.authorizationCode)
        .catch((error: unknown) =>
          this.logger.warn(
            `เก็บ refresh token ของ Apple ไม่สำเร็จ: ${error instanceof Error ? error.message : error}`,
          ),
        );
    }

    if (input.app === 'provider') return this.providerSession(appleUserId);

    const name = input.fullName?.trim().slice(0, 120) || undefined;
    const customer = await this.prisma.customer.upsert({
      where: { appleUserId },
      create: { appleUserId, name },
      update: {},
    });
    if (customer.deletedAt) {
      throw new UnauthorizedException('บัญชีนี้ถูกลบแล้ว');
    }
    const payload: JwtPayload = {
      sub: customer.id,
      role: Role.CUSTOMER,
      phone: customer.phone ?? '',
    };
    return {
      accessToken: await this.jwt.signAsync(payload),
      hasProfile: true,
      userId: customer.id,
    };
  }

  /** ช่างที่เคยสมัครด้วย Apple นี้เข้าบัญชีเดิม คนใหม่ได้โทเคนสำหรับส่งใบสมัคร */
  private async providerSession(appleUserId: string) {
    const provider = await this.prisma.provider.findUnique({
      where: { appleUserId },
      select: { id: true, phone: true, deletedAt: true },
    });
    if (provider && !provider.deletedAt) {
      const payload: JwtPayload = {
        sub: provider.id,
        role: Role.PROVIDER,
        phone: provider.phone,
      };
      return {
        accessToken: await this.jwt.signAsync(payload),
        hasProfile: true,
        userId: provider.id,
      };
    }
    const payload: JwtPayload = {
      sub: `pending:apple:${appleUserId}`,
      role: Role.PROVIDER,
      phone: '',
      appleUserId,
    };
    return {
      accessToken: await this.jwt.signAsync(payload),
      hasProfile: false,
      userId: null,
    };
  }

  /** คืน sub (Apple userId) เมื่อ token ถูกต้องทุกข้อ ไม่งั้นโยน 401 */
  async verifyIdentityToken(
    token: string,
    rawNonce: string,
    audience: string,
    now: number = Date.now(),
  ): Promise<string> {
    const parts = token.split('.');
    if (parts.length !== 3) {
      throw new UnauthorizedException('ข้อมูลจาก Apple ไม่ถูกต้อง');
    }
    const [headerPart, claimsPart, signaturePart] = parts;
    let header: { alg?: string; kid?: string };
    let claims: AppleClaims;
    try {
      header = decodeJson(headerPart);
      claims = decodeJson(claimsPart);
    } catch {
      throw new UnauthorizedException('ข้อมูลจาก Apple ไม่ถูกต้อง');
    }
    if (header.alg !== 'RS256' || !header.kid) {
      throw new UnauthorizedException('ข้อมูลจาก Apple ไม่ถูกต้อง');
    }
    const key = await this.publicKey(header.kid, now);
    const valid = cryptoVerify(
      'RSA-SHA256',
      Buffer.from(`${headerPart}.${claimsPart}`),
      key,
      Buffer.from(signaturePart, 'base64url'),
    );
    if (!valid) throw new UnauthorizedException('ลายเซ็นของ Apple ไม่ถูกต้อง');

    const nowSeconds = Math.floor(now / 1000);
    if (claims.iss !== APPLE_ISSUER || claims.aud !== audience) {
      throw new UnauthorizedException('ข้อมูลจาก Apple ไม่ใช่ของแอปนี้');
    }
    if (!claims.exp || claims.exp + CLOCK_SKEW_SECONDS < nowSeconds) {
      throw new UnauthorizedException(
        'ข้อมูลจาก Apple หมดอายุ ลองใหม่อีกครั้ง',
      );
    }
    const expectedNonce = createHash('sha256').update(rawNonce).digest('hex');
    if (!rawNonce || !claims.nonce || !safeEqual(claims.nonce, expectedNonce)) {
      throw new UnauthorizedException('ข้อมูลจาก Apple ไม่ตรงกับคำขอ');
    }
    if (!claims.sub) throw new UnauthorizedException('Apple ไม่ส่ง userId');

    for (const [used, expiry] of this.usedTokens) {
      if (expiry < nowSeconds) this.usedTokens.delete(used);
    }
    if (this.usedTokens.has(signaturePart)) {
      throw new UnauthorizedException('ข้อมูลนี้ถูกใช้ไปแล้ว ลองใหม่อีกครั้ง');
    }
    this.usedTokens.set(signaturePart, claims.exp + CLOCK_SKEW_SECONDS);
    return claims.sub;
  }

  private async publicKey(kid: string, now: number): Promise<KeyObject> {
    const fresh = now - this.keysLoadedAt < KEYS_TTL_MS;
    if (!fresh || !this.keys.has(kid)) await this.loadKeys(now);
    const key = this.keys.get(kid);
    if (!key) throw new UnauthorizedException('ไม่รู้จักกุญแจของ Apple');
    return key;
  }

  private async loadKeys(now: number) {
    const response = await fetch(KEYS_URL);
    if (!response.ok) {
      this.logger.warn(
        `โหลด public key ของ Apple ไม่สำเร็จ: ${response.status}`,
      );
      throw new UnauthorizedException('ติดต่อ Apple ไม่สำเร็จ ลองใหม่อีกครั้ง');
    }
    const { keys } = (await response.json()) as { keys?: AppleJwk[] };
    const loaded = new Map<string, KeyObject>();
    for (const jwk of keys ?? []) {
      try {
        loaded.set(jwk.kid, createPublicKey({ key: jwk, format: 'jwk' }));
      } catch {
        // ข้าม key ที่อ่านไม่ได้
      }
    }
    this.keys = loaded;
    this.keysLoadedAt = now;
  }
}
