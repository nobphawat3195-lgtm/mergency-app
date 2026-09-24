import { Logger } from '@nestjs/common';
import { createSign } from 'node:crypto';

export interface PushMessage {
  title: string;
  body: string;
  /** ข้อมูลให้แอปนำทางต่อ เช่น { type: 'OFFER', orderId } ค่าทุกตัวต้องเป็น string ตาม FCM */
  data: Record<string, string>;
}

/** ผลส่งต่อเครื่อง: invalid = โทเคนใช้ไม่ได้แล้ว (ถอนแอป/ล็อกเอาต์) ต้องลบทิ้ง */
export type PushResult = 'sent' | 'invalid' | 'failed';

export interface PushSender {
  readonly name: string;
  send(token: string, message: PushMessage): Promise<PushResult>;
}

type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

/** ใช้ตอนพัฒนา: พิมพ์ข้อความลง log แทนการส่งจริง */
export class ConsolePushSender implements PushSender {
  readonly name = 'console';
  private readonly logger = new Logger('ConsolePush');

  async send(token: string, message: PushMessage): Promise<PushResult> {
    this.logger.debug(
      `push → ${token.slice(0, 12)}…: ${message.title} | ${message.body} ${JSON.stringify(message.data)}`,
    );
    return 'sent';
  }
}

export interface FcmCredentials {
  projectId: string;
  clientEmail: string;
  /** PEM ของ service account (ใน env ใส่ \n แทนขึ้นบรรทัดใหม่ได้) */
  privateKey: string;
}

function base64url(input: string | Buffer): string {
  return Buffer.from(input).toString('base64url');
}

/**
 * ส่งผ่าน Firebase Cloud Messaging HTTP v1 (ครอบทั้ง Android และ iOS ผ่าน APNs key ที่อัปโหลดใน Firebase)
 *
 * ขอ OAuth access token ด้วย JWT ที่เซ็นจาก service account เอง ไม่ต้องพึ่ง firebase-admin
 * token อายุ 1 ชม. แคชไว้ใช้ซ้ำจนใกล้หมดอายุ
 */
export class FcmPushSender implements PushSender {
  readonly name = 'fcm';
  private readonly logger = new Logger('FcmPush');
  private accessToken: { value: string; expiresAt: number } | null = null;

  constructor(
    private readonly credentials: FcmCredentials,
    private readonly fetchImpl: FetchLike = fetch as unknown as FetchLike,
    private readonly now: () => number = Date.now,
  ) {}

  private async getAccessToken(): Promise<string> {
    if (this.accessToken && this.accessToken.expiresAt - 60_000 > this.now()) {
      return this.accessToken.value;
    }
    const issuedAt = Math.floor(this.now() / 1000);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = base64url(
      JSON.stringify({
        iss: this.credentials.clientEmail,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: issuedAt,
        exp: issuedAt + 3600,
      }),
    );
    const signer = createSign('RSA-SHA256');
    signer.update(`${header}.${claims}`);
    const signature = signer
      .sign(this.credentials.privateKey)
      .toString('base64url');

    const response = await this.fetchImpl(
      'https://oauth2.googleapis.com/token',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion: `${header}.${claims}.${signature}`,
        }).toString(),
      },
    );
    if (!response.ok) {
      throw new Error(`FCM OAuth ล้มเหลว HTTP ${response.status}`);
    }
    const payload = (await response.json()) as {
      access_token: string;
      expires_in: number;
    };
    this.accessToken = {
      value: payload.access_token,
      expiresAt: this.now() + payload.expires_in * 1000,
    };
    return payload.access_token;
  }

  async send(token: string, message: PushMessage): Promise<PushResult> {
    const accessToken = await this.getAccessToken();
    const response = await this.fetchImpl(
      `https://fcm.googleapis.com/v1/projects/${this.credentials.projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: message.title, body: message.body },
            data: message.data,
            android: {
              priority: 'HIGH',
              notification: { sound: 'default', channel_id: 'fixgo_updates' },
            },
            apns: {
              headers: { 'apns-priority': '10' },
              payload: { aps: { sound: 'default' } },
            },
          },
        }),
      },
    );
    if (response.ok) return 'sent';

    const error = (await response.json().catch(() => ({}))) as {
      error?: { status?: string; details?: { errorCode?: string }[] };
    };
    const codes = [
      error.error?.status,
      ...(error.error?.details ?? []).map((detail) => detail.errorCode),
    ];
    // 404 UNREGISTERED = แอปถูกลบ/โทเคนหมดอายุ, INVALID_ARGUMENT บนโทเคน = โทเคนผิดรูป
    if (
      response.status === 404 ||
      codes.includes('UNREGISTERED') ||
      (response.status === 400 && codes.includes('INVALID_ARGUMENT'))
    ) {
      return 'invalid';
    }
    this.logger.warn(
      `FCM ส่งไม่สำเร็จ HTTP ${response.status} ${codes.join(',')}`,
    );
    return 'failed';
  }
}

export function readFcmCredentials(
  env: NodeJS.ProcessEnv = process.env,
): FcmCredentials | null {
  const projectId = env.FCM_PROJECT_ID?.trim();
  const clientEmail = env.FCM_CLIENT_EMAIL?.trim();
  const privateKey = env.FCM_PRIVATE_KEY?.replace(/\\n/g, '\n').trim();
  if (!projectId || !clientEmail || !privateKey) return null;
  return { projectId, clientEmail, privateKey };
}

export function createPushSender(
  env: NodeJS.ProcessEnv = process.env,
): PushSender {
  const provider = env.PUSH_PROVIDER?.trim() || 'console';
  if (provider === 'fcm') {
    const credentials = readFcmCredentials(env);
    if (!credentials) {
      throw new Error(
        'PUSH_PROVIDER=fcm ต้องตั้ง FCM_PROJECT_ID, FCM_CLIENT_EMAIL และ FCM_PRIVATE_KEY',
      );
    }
    return new FcmPushSender(credentials);
  }
  return new ConsolePushSender();
}

export const PUSH_SENDER = Symbol('PUSH_SENDER');
