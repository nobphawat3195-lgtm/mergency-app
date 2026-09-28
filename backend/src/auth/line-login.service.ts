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
import {
  publicApiUrl,
  publicFixerUrl,
  publicWebUrl,
  readSecret,
} from '../config/environment';
import { JwtPayload } from './auth.service';

const AUTHORIZE_URL = 'https://access.line.me/oauth2/v2.1/authorize';
const TOKEN_URL = 'https://api.line.me/oauth2/v2.1/token';
const VERIFY_URL = 'https://api.line.me/oauth2/v2.1/verify';

/** เวลาที่ผู้ใช้มีเพื่อกดยอมรับในหน้า LINE */
const STATE_TTL_MS = 10 * 60_000;
/** ตั๋วแลกโทเคนหลังกลับมาที่เว็บ ใช้ได้ครั้งเดียวภายในเวลานี้ */
const TICKET_TTL_MS = 60_000;

export const LINE_STATE_COOKIE = 'fixgo_line_state';

/** แอปที่เริ่มล็อกอิน: ใช้เลือกว่าจะสร้างบัญชีแบบไหนและพากลับไปเว็บไหน */
export type LineApp = 'customer' | 'provider';

export function parseLineApp(value: unknown): LineApp {
  return value === 'provider' ? 'provider' : 'customer';
}

interface LineConfig {
  channelId: string;
  channelSecret: string;
  callbackUrl: string;
  webUrl: string;
}

/**
 * ล็อกอินด้วย LINE (OAuth 2.1 + OpenID Connect) สำหรับเว็บลูกค้าและเว็บแอปช่าง
 * ใช้ LINE Login channel และ Callback URL เดียวกันทั้งสองแอป แยกด้วยค่า app ในคุกกี้ state
 *
 * 1. /start สร้าง state + nonce เก็บในคุกกี้ที่ลงลายเซ็นไว้ แล้วพาไปหน้า LINE
 * 2. LINE พากลับมา /callback พร้อม code ตรวจ state กับคุกกี้ (กัน CSRF)
 *    แลก code เป็น id_token แล้วให้ LINE ตรวจ id_token + nonce ให้
 * 3. พากลับเว็บพร้อม "ตั๋ว" อายุ 60 วินาที ใช้ได้ครั้งเดียว เว็บเอาตั๋วมาแลก accessToken
 *    (ไม่ใส่ accessToken ใน URL ตรงๆ เพราะ URL ไปอยู่ในประวัติเบราว์เซอร์และ log)
 *
 * LINE ไม่ส่งเบอร์โทรมา ลูกค้าที่สมัครด้วย LINE จึงไม่มีเบอร์ (phone = null)
 * ช่างที่ยังไม่มีบัญชีได้โทเคนชั่วคราว (sub = pending:line:<LINE userId>) ไว้ส่งใบสมัคร
 * และกรอกเบอร์ติดต่อเองในใบสมัคร
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

  private config(app: LineApp): LineConfig | null {
    const channelId = process.env.LINE_LOGIN_CHANNEL_ID?.trim();
    const channelSecret = process.env.LINE_LOGIN_CHANNEL_SECRET?.trim();
    const webUrl = app === 'provider' ? publicFixerUrl() : publicWebUrl();
    if (!channelId || !channelSecret || !webUrl) return null;
    return {
      channelId,
      channelSecret,
      callbackUrl: `${publicApiUrl()}/api/auth/line/callback`,
      webUrl,
    };
  }

  isEnabled(app: LineApp = 'customer'): boolean {
    return this.config(app) !== null;
  }

  private requireConfig(app: LineApp): LineConfig {
    const config = this.config(app);
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
  start(app: LineApp = 'customer', now: number = Date.now()) {
    const config = this.requireConfig(app);
    const state = randomBytes(16).toString('base64url');
    const nonce = randomBytes(16).toString('base64url');
    const body = `${state}.${nonce}.${now + STATE_TTL_MS}.${app}`;
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

  /** แอปที่เริ่มล็อกอิน อ่านจากคุกกี้ (ยังไม่ตรวจลายเซ็น ใช้เลือกหน้าที่จะพากลับเท่านั้น) */
  appFromCookie(cookie: string | undefined): LineApp {
    return parseLineApp(cookie?.split('.')[3]);
  }

  /** หน้าเว็บที่จะพาผู้ใช้กลับไปเมื่อเกิดข้อผิดพลาด */
  failureRedirect(app: LineApp = 'customer'): string {
    const webUrl =
      (app === 'provider' ? publicFixerUrl() : publicWebUrl()) ?? '/';
    return `${webUrl}/?line_error=1`;
  }

  /** ตรวจ state, แลก code, ตรวจ id_token แล้วคืน URL เว็บพร้อมตั๋วแลกโทเคน */
  async callback(
    query: { code?: string; state?: string; error?: string },
    cookie: string | undefined,
    now: number = Date.now(),
  ): Promise<string> {
    if (query.error || !query.code || !query.state) {
      throw new UnauthorizedException('ผู้ใช้ยกเลิกหรือ LINE ส่งข้อมูลไม่ครบ');
    }
    const parts = cookie?.split('.') ?? [];
    if (parts.length !== 5) throw new UnauthorizedException('ไม่พบ state');
    const [state, nonce, expires, appValue, signature] = parts;
    if (
      !this.verifySigned(
        `${state}.${nonce}.${expires}.${appValue}`,
        signature,
        'line-state',
      ) ||
      state !== query.state ||
      Number(expires) < now
    ) {
      throw new UnauthorizedException('state ไม่ตรงหรือหมดอายุ');
    }
    const app = parseLineApp(appValue);
    const config = this.requireConfig(app);

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

    if (app === 'provider') {
      // ช่างยังไม่สร้างบัญชีตรงนี้ ต้องส่งใบสมัครก่อน ตั๋วจึงพา LINE userId ไปแทน
      const ticket = this.issueTicket('provider', profile.sub, now);
      return `${config.webUrl}/?line_ticket=${encodeURIComponent(ticket)}`;
    }

    const customer = await this.prisma.customer.upsert({
      where: { lineUserId: profile.sub },
      create: { lineUserId: profile.sub, name: profile.name?.slice(0, 120) },
      update: {},
    });
    if (customer.deletedAt) {
      throw new UnauthorizedException('บัญชีนี้ถูกลบแล้ว');
    }

    const ticket = this.issueTicket('customer', customer.id, now);
    return `${config.webUrl}/?line_ticket=${encodeURIComponent(ticket)}`;
  }

  /** subject = id ลูกค้า หรือ LINE userId ของช่าง (ไม่มีจุดทั้งคู่) */
  private issueTicket(app: LineApp, subject: string, now: number): string {
    const body = `${app}.${subject}.${now + TICKET_TTL_MS}.${randomBytes(12).toString('base64url')}`;
    return `${Buffer.from(body).toString('base64url')}.${this.sign(body, 'line-ticket')}`;
  }

  /** เว็บเอาตั๋วมาแลก accessToken (ครั้งเดียว ภายใน 60 วินาที) */
  async exchange(ticket: string, now: number = Date.now()) {
    const [encoded, signature] = ticket.split('.');
    const body = encoded ? Buffer.from(encoded, 'base64url').toString() : '';
    const [app, subject, expires] = body.split('.');
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

    if (app === 'provider') return this.providerSession(subject);

    const customer = await this.prisma.customer.findUnique({
      where: { id: subject },
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

  /** ช่างที่เคยสมัครด้วย LINE นี้แล้วเข้าบัญชีเดิม คนใหม่ได้โทเคนสำหรับส่งใบสมัคร */
  private async providerSession(lineUserId: string) {
    const provider = await this.prisma.provider.findUnique({
      where: { lineUserId },
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
      sub: `pending:line:${lineUserId}`,
      role: Role.PROVIDER,
      phone: '',
      lineUserId,
    };
    return {
      accessToken: await this.jwt.signAsync(payload),
      hasProfile: false,
      userId: null,
    };
  }
}
