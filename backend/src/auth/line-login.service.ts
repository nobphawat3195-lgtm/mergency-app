import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
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

/** เริ่มจากเว็บ หรือจากแอปมือถือ (iOS/Android) ค่าอื่นถือเป็นเว็บ */
export type LineClient = 'web' | 'native';

export function parseLineClient(value: unknown): LineClient {
  return value === 'native' ? 'native' : 'web';
}

/**
 * ที่อยู่กลับเข้าแอปมือถือ (custom scheme) อนุญาตเฉพาะ 2 ค่านี้
 * ไม่รับ redirect URL จาก query เด็ดขาด กันการพาตั๋วไปให้แอปอื่น
 */
const NATIVE_RETURN_URLS: Record<LineApp, string> = {
  customer: 'fixgo://auth/line',
  provider: 'fixgofixer://auth/line',
};

interface LineConfig {
  channelId: string;
  channelSecret: string;
  callbackUrl: string;
  webUrl: string;
}

/**
 * ล็อกอินด้วย LINE (OAuth 2.1 + OpenID Connect) สำหรับเว็บลูกค้าและเว็บแอปช่าง
 * ใช้ LINE Login channel และ Callback URL เดียวกันทั้งสองแอป แยกด้วยค่า app ใน state
 *
 * 1. /start สร้าง state ที่ลงลายเซ็นไว้ (random.nonce.expires.app.hmac) ส่งให้ LINE
 *    และเก็บค่าเดียวกันในคุกกี้ แล้วพาไปหน้า LINE
 * 2. LINE พากลับมา /callback พร้อม code ตรวจลายเซ็นและอายุของ state
 *    ถ้ามีคุกกี้ต้องตรงกับ state (กัน CSRF) ถ้าคุกกี้หาย (iPhone เปิดล็อกอินในเบราว์เซอร์ของ
 *    แอป LINE แล้วกลับมาอีกเบราว์เซอร์) ยังล็อกอินต่อได้ด้วย state ที่ลายเซ็นถูกและยังไม่เคยใช้
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
  /** state ที่ใช้ไปแล้ว (เก็บจนหมดอายุ) callback ซ้ำด้วย state เดิมไม่ผ่าน */
  private readonly usedStates = new Map<string, number>();

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

  /**
   * คืน URL หน้า LINE และค่าคุกกี้ state ที่ต้องตั้งก่อน redirect
   * state ที่ส่งให้ LINE กับคุกกี้เป็นค่าเดียวกัน: callback จึงรู้ว่าเริ่มจากแอปไหน
   * (และจากเว็บหรือแอปมือถือ) แม้คุกกี้หาย
   */
  start(
    app: LineApp = 'customer',
    now: number = Date.now(),
    client: LineClient = 'web',
  ) {
    const config = this.requireConfig(app);
    const random = randomBytes(16).toString('base64url');
    const nonce = randomBytes(16).toString('base64url');
    const body = `${random}.${nonce}.${now + STATE_TTL_MS}.${app}.${client}`;
    const state = `${body}.${this.sign(body, 'line-state')}`;
    const cookie = state;
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

  /**
   * แยก state ที่ลงลายเซ็นไว้ (random.nonce.expires.app.client.hmac)
   * คืน null ถ้ารูปแบบหรือลายเซ็นไม่ถูก (ไม่ตรวจอายุ)
   */
  private parseState(value: string | undefined) {
    const parts = value?.split('.') ?? [];
    if (parts.length !== 6) return null;
    const [random, nonce, expires, appValue, clientValue, signature] = parts;
    if (
      !this.verifySigned(
        `${random}.${nonce}.${expires}.${appValue}.${clientValue}`,
        signature,
        'line-state',
      )
    ) {
      return null;
    }
    return {
      nonce,
      expires: Number(expires),
      app: parseLineApp(appValue),
      client: parseLineClient(clientValue),
    };
  }

  /**
   * ที่จะพากลับเมื่อล็อกอินไม่สำเร็จ: เชื่อเฉพาะ state/คุกกี้ที่ลายเซ็นถูก
   * อ่านไม่ได้ทั้งคู่จึงพากลับเว็บลูกค้า
   */
  failureTarget(
    state: string | undefined,
    cookie: string | undefined,
  ): { app: LineApp; client: LineClient } {
    const parsed = this.parseState(state) ?? this.parseState(cookie);
    return parsed
      ? { app: parsed.app, client: parsed.client }
      : { app: 'customer', client: 'web' };
  }

  /** แอปที่จะพากลับเมื่อล็อกอินไม่สำเร็จ */
  failureApp(state: string | undefined, cookie: string | undefined): LineApp {
    return this.failureTarget(state, cookie).app;
  }

  /** หน้าเว็บหรือแอปมือถือที่จะพาผู้ใช้กลับไปเมื่อเกิดข้อผิดพลาด */
  failureRedirect(
    app: LineApp = 'customer',
    client: LineClient = 'web',
  ): string {
    if (client === 'native') return `${NATIVE_RETURN_URLS[app]}?line_error=1`;
    const webUrl =
      (app === 'provider' ? publicFixerUrl() : publicWebUrl()) ?? '/';
    return `${webUrl}/?line_error=1`;
  }

  /** ที่อยู่รับตั๋ว: เว็บของแอปนั้น หรือ custom scheme ของแอปมือถือ (allow-list) */
  private ticketRedirect(
    app: LineApp,
    client: LineClient,
    webUrl: string,
    ticket: string,
  ): string {
    const base = client === 'native' ? NATIVE_RETURN_URLS[app] : `${webUrl}/`;
    return `${base}?line_ticket=${encodeURIComponent(ticket)}`;
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
    const parsed = this.parseState(query.state);
    if (!parsed) throw new UnauthorizedException('state ลายเซ็นไม่ถูก');
    if (parsed.expires < now) throw new UnauthorizedException('state หมดอายุ');
    // มีคุกกี้ (เบราว์เซอร์เดิม) ต้องตรงกัน กันการยัด state ของคนอื่นมา
    if (cookie !== undefined && cookie !== query.state) {
      throw new UnauthorizedException('state ไม่ตรงกับคุกกี้');
    }
    for (const [used, expiry] of this.usedStates) {
      if (expiry < now) this.usedStates.delete(used);
    }
    if (this.usedStates.has(query.state)) {
      throw new UnauthorizedException('state นี้ถูกใช้ไปแล้ว');
    }
    this.usedStates.set(query.state, parsed.expires);
    const { app, nonce, client } = parsed;
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
      return this.ticketRedirect(app, client, config.webUrl, ticket);
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
    return this.ticketRedirect(app, client, config.webUrl, ticket);
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

  /**
   * เปลี่ยน pending token (sub = pending:line:<id>) ที่ค้างอยู่ในเบราว์เซอร์อื่นเป็นโทเคนช่างตัวจริง
   * เมื่อบัญชี LINE นี้ส่งใบสมัครไปแล้วจากที่อื่น ยังไม่สมัครคืน 404 ให้แอปพาไปหน้าสมัครเหมือนเดิม
   *
   * ใช้ได้เฉพาะ pending token ของ LINE: เจ้าของโทเคนยืนยันตัวตนกับ LINE มาแล้วตอนล็อกอิน
   * ผลจึงเท่ากับการล็อกอิน LINE ใหม่ (ดู providerSession)
   */
  async refreshPendingProvider(user: JwtPayload) {
    const lineUserId = user.sub.startsWith('pending:line:')
      ? user.sub.slice('pending:line:'.length)
      : '';
    if (
      user.role !== Role.PROVIDER ||
      !lineUserId ||
      user.lineUserId !== lineUserId
    ) {
      throw new ForbiddenException(
        'ใช้ได้เฉพาะช่างที่เข้าด้วย LINE และยังไม่ได้สมัคร',
      );
    }
    const session = await this.providerSession(lineUserId);
    if (!session.hasProfile) {
      throw new NotFoundException('บัญชี LINE นี้ยังไม่ได้ส่งใบสมัครช่าง');
    }
    return session;
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
