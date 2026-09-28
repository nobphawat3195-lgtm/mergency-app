import {
  BadRequestException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Role } from '@prisma/client';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';
import { publicApiUrl, publicWebUrl, readSecret } from '../config/environment';
import { JwtPayload } from './auth.service';

const AUTHORIZE_URL = 'https://access.line.me/oauth2/v2.1/authorize';
const TOKEN_URL = 'https://api.line.me/oauth2/v2.1/token';
const VERIFY_URL = 'https://api.line.me/oauth2/v2.1/verify';

/** เวลาที่ผู้ใช้มีเพื่อกดยอมรับในหน้า LINE */
const STATE_TTL_MS = 10 * 60_000;
/** ตั๋วแลกโทเคนหลังกลับมาที่เว็บ ใช้ได้ครั้งเดียวภายในเวลานี้ */
const TICKET_TTL_MS = 60_000;

export const LINE_STATE_COOKIE = 'fixgo_line_state';

interface LineConfig {
  channelId: string;
  channelSecret: string;
  callbackUrl: string;
  webUrl: string;
}

/**
 * ล็อกอินลูกค้าด้วย LINE (OAuth 2.1 + OpenID Connect) สำหรับเว็บลูกค้า
 *
 * 1. /start สร้าง state + nonce เก็บในคุกกี้ที่ลงลายเซ็นไว้ แล้วพาไปหน้า LINE
 * 2. LINE พากลับมา /callback พร้อม code ตรวจ state กับคุกกี้ (กัน CSRF)
 *    แลก code เป็น id_token แล้วให้ LINE ตรวจ id_token + nonce ให้
 * 3. พากลับเว็บพร้อม "ตั๋ว" อายุ 60 วินาที ใช้ได้ครั้งเดียว เว็บเอาตั๋วมาแลก accessToken
 *    (ไม่ใส่ accessToken ใน URL ตรงๆ เพราะ URL ไปอยู่ในประวัติเบราว์เซอร์และ log)
 *
 * LINE ไม่ส่งเบอร์โทรมา บัญชีที่สมัครด้วย LINE จึงไม่มีเบอร์ (phone = null)
 */
@Injectable()
export class LineLoginService {
  private readonly logger = new Logger(LineLoginService.name);
  /** ตั๋วที่ใช้ไปแล้ว (เก็บจนหมดอายุ) กันการใช้ซ้ำ */
  private readonly usedTickets = new Map<string, number>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  private config(): LineConfig | null {
    const channelId = process.env.LINE_LOGIN_CHANNEL_ID?.trim();
    const channelSecret = process.env.LINE_LOGIN_CHANNEL_SECRET?.trim();
    const webUrl = publicWebUrl();
    if (!channelId || !channelSecret || !webUrl) return null;
    return {
      channelId,
      channelSecret,
      callbackUrl: `${publicApiUrl()}/api/auth/line/callback`,
      webUrl,
    };
  }

  isEnabled(): boolean {
    return this.config() !== null;
  }

  private requireConfig(): LineConfig {
    const config = this.config();
    if (!config) {
      throw new BadRequestException('ยังไม่ได้เปิดใช้การเข้าสู่ระบบด้วย LINE');
    }
    return config;
  }

  private sign(value: string, purpose: string): string {
    return createHmac(
      'sha256',
      `${purpose}:${readSecret('JWT_SECRET', 'dev-jwt-secret')}`,
    )
      .update(value)
      .digest('base64url');
  }

  private verifySigned(value: string, signature: string, purpose: string) {
    const expected = Buffer.from(this.sign(value, purpose));
    const actual = Buffer.from(signature);
    return (
      expected.length === actual.length && timingSafeEqual(expected, actual)
    );
  }

  /** คืน URL หน้า LINE และค่าคุกกี้ state ที่ต้องตั้งก่อน redirect */
  start(now: number = Date.now()) {
    const config = this.requireConfig();
    const state = randomBytes(16).toString('base64url');
    const nonce = randomBytes(16).toString('base64url');
    const body = `${state}.${nonce}.${now + STATE_TTL_MS}`;
    const cookie = `${body}.${this.sign(body, 'line-state')}`;
    const url = new URL(AUTHORIZE_URL);
    url.search = new URLSearchParams({
      response_type: 'code',
      client_id: config.channelId,
      redirect_uri: config.callbackUrl,
      state,
      scope: 'profile openid',
      nonce,
    }).toString();
    return { url: url.toString(), cookie, maxAgeSeconds: STATE_TTL_MS / 1000 };
  }

  /** หน้าเว็บที่จะพาผู้ใช้กลับไปเมื่อเกิดข้อผิดพลาด */
  failureRedirect(): string {
    const webUrl = publicWebUrl() ?? '/';
    return `${webUrl}/?line_error=1`;
  }

  /** ตรวจ state, แลก code, ตรวจ id_token แล้วคืน URL เว็บพร้อมตั๋วแลกโทเคน */
  async callback(
    query: { code?: string; state?: string; error?: string },
    cookie: string | undefined,
    now: number = Date.now(),
  ): Promise<string> {
    const config = this.requireConfig();
    if (query.error || !query.code || !query.state) {
      throw new UnauthorizedException('ผู้ใช้ยกเลิกหรือ LINE ส่งข้อมูลไม่ครบ');
    }
    const parts = cookie?.split('.') ?? [];
    if (parts.length !== 4) throw new UnauthorizedException('ไม่พบ state');
    const [state, nonce, expires, signature] = parts;
    if (
      !this.verifySigned(
        `${state}.${nonce}.${expires}`,
        signature,
        'line-state',
      ) ||
      state !== query.state ||
      Number(expires) < now
    ) {
      throw new UnauthorizedException('state ไม่ตรงหรือหมดอายุ');
    }

    const tokenResponse = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: query.code,
        redirect_uri: config.callbackUrl,
        client_id: config.channelId,
        client_secret: config.channelSecret,
      }),
    });
    if (!tokenResponse.ok) {
      this.logger.warn(`LINE token exchange failed: ${tokenResponse.status}`);
      throw new UnauthorizedException('แลกรหัสกับ LINE ไม่สำเร็จ');
    }
    const { id_token: idToken } = (await tokenResponse.json()) as {
      id_token?: string;
    };
    if (!idToken) throw new UnauthorizedException('LINE ไม่ส่ง id_token');

    // ให้ LINE ตรวจลายเซ็น อายุ ผู้รับ (channel) และ nonce ของ id_token ให้
    const verifyResponse = await fetch(VERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        id_token: idToken,
        client_id: config.channelId,
        nonce,
      }),
    });
    if (!verifyResponse.ok) {
      this.logger.warn(`LINE id_token verify failed: ${verifyResponse.status}`);
      throw new UnauthorizedException('ตรวจข้อมูลจาก LINE ไม่ผ่าน');
    }
    const profile = (await verifyResponse.json()) as {
      sub?: string;
      name?: string;
    };
    if (!profile.sub) throw new UnauthorizedException('LINE ไม่ส่ง userId');

    const customer = await this.prisma.customer.upsert({
      where: { lineUserId: profile.sub },
      create: { lineUserId: profile.sub, name: profile.name?.slice(0, 120) },
      update: {},
    });
    if (customer.deletedAt) {
      throw new UnauthorizedException('บัญชีนี้ถูกลบแล้ว');
    }

    const ticket = this.issueTicket(customer.id, now);
    return `${config.webUrl}/?line_ticket=${encodeURIComponent(ticket)}`;
  }

  private issueTicket(customerId: string, now: number): string {
    const body = `${customerId}.${now + TICKET_TTL_MS}.${randomBytes(12).toString('base64url')}`;
    return `${Buffer.from(body).toString('base64url')}.${this.sign(body, 'line-ticket')}`;
  }

  /** เว็บเอาตั๋วมาแลก accessToken (ครั้งเดียว ภายใน 60 วินาที) */
  async exchange(ticket: string, now: number = Date.now()) {
    const [encoded, signature] = ticket.split('.');
    const body = encoded ? Buffer.from(encoded, 'base64url').toString() : '';
    const [customerId, expires] = body.split('.');
    if (
      !signature ||
      !this.verifySigned(body, signature, 'line-ticket') ||
      Number(expires) < now
    ) {
      throw new UnauthorizedException('ตั๋วเข้าสู่ระบบหมดอายุ กรุณาลองใหม่');
    }
    for (const [used, expiry] of this.usedTickets) {
      if (expiry < now) this.usedTickets.delete(used);
    }
    if (this.usedTickets.has(body)) {
      throw new UnauthorizedException('ตั๋วนี้ถูกใช้ไปแล้ว');
    }
    this.usedTickets.set(body, Number(expires));

    const customer = await this.prisma.customer.findUnique({
      where: { id: customerId },
    });
    if (!customer || customer.deletedAt) {
      throw new UnauthorizedException('ไม่พบบัญชี');
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
}
