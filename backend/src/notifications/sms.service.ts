import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';

type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

export function toThaiE164(phone: string): string {
  if (phone.startsWith('+')) return phone;
  if (phone.startsWith('0')) return `+66${phone.slice(1)}`;
  return phone;
}

export function otpMessage(code: string): string {
  return `รหัส FixGo OTP ของคุณคือ ${code} ใช้ได้ 5 นาที ห้ามบอกรหัสนี้กับผู้อื่น`;
}

function basicAuth(user: string, password: string): string {
  return `Basic ${Buffer.from(`${user}:${password}`).toString('base64')}`;
}

export interface SmsSender {
  readonly name: string;
  /** ส่งไม่สำเร็จต้อง throw เพื่อให้ผู้ใช้กดขอรหัสใหม่ได้ */
  send(phone: string, message: string): Promise<void>;
}

export class TwilioSmsSender implements SmsSender {
  readonly name = 'twilio';
  private readonly logger = new Logger('TwilioSms');

  constructor(
    private readonly config: {
      accountSid: string;
      authToken: string;
      from: string;
    },
    private readonly fetchImpl: FetchLike = fetch as unknown as FetchLike,
  ) {}

  async send(phone: string, message: string): Promise<void> {
    const { accountSid, authToken, from } = this.config;
    const response = await this.fetchImpl(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: basicAuth(accountSid, authToken),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          To: toThaiE164(phone),
          From: from,
          Body: message,
        }).toString(),
      },
    );
    if (!response.ok) {
      this.logger.error(`Twilio ตอบ HTTP ${response.status}`);
      throw new Error(`twilio HTTP ${response.status}`);
    }
  }
}

/**
 * ThaiBulkSMS API v2: POST https://api-v2.thaibulksms.com/sms
 * Basic auth (API Key / API Secret) body แบบ form: msisdn, message, sender, force
 *
 * force=corporate ส่งผ่านเส้นทางผู้ส่งที่ลงทะเบียนแล้ว เหมาะกับ OTP (standard อาจช้าหรือตกหล่น)
 * ชื่อผู้ส่งต้องยื่นขออนุมัติในหลังบ้าน ThaiBulkSMS ก่อนใช้
 */
export class ThaiBulkSmsSender implements SmsSender {
  readonly name = 'thaibulksms';
  private readonly logger = new Logger('ThaiBulkSms');

  constructor(
    private readonly config: {
      apiKey: string;
      apiSecret: string;
      sender: string;
      force: 'corporate' | 'standard';
    },
    private readonly fetchImpl: FetchLike = fetch as unknown as FetchLike,
  ) {}

  async send(phone: string, message: string): Promise<void> {
    const response = await this.fetchImpl(
      'https://api-v2.thaibulksms.com/sms',
      {
        method: 'POST',
        headers: {
          Authorization: basicAuth(this.config.apiKey, this.config.apiSecret),
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
        body: new URLSearchParams({
          msisdn: phone,
          message,
          sender: this.config.sender,
          force: this.config.force,
        }).toString(),
      },
    );
    const payload = (await response.json().catch(() => ({}))) as {
      bad_phone_number_list?: unknown[];
      error?: { code?: number | string; name?: string };
    };
    if (!response.ok) {
      this.logger.error(
        `ThaiBulkSMS ตอบ HTTP ${response.status} ${payload.error?.name ?? ''} ${payload.error?.code ?? ''}`,
      );
      throw new Error(`thaibulksms HTTP ${response.status}`);
    }
    // ตอบ 2xx แต่เบอร์อยู่ในรายการเบอร์เสีย = ไม่ได้ส่งจริง
    if (payload.bad_phone_number_list?.length) {
      this.logger.warn('ThaiBulkSMS ปฏิเสธเบอร์ปลายทาง');
      throw new Error('thaibulksms rejected phone number');
    }
  }
}

export class ConsoleSmsSender implements SmsSender {
  readonly name = 'console';
  private readonly logger = new Logger('ConsoleSms');

  async send(phone: string, message: string): Promise<void> {
    this.logger.debug(`SMS → ${phone}: ${message}`);
  }
}

/**
 * คืน null เมื่อยังตั้งค่าไม่ครบ SmsService จะตอบ 503 แทนการล่มตอนเปิดเซิร์ฟเวอร์
 * (production ตรวจค่าครบตั้งแต่เริ่มใน validateEnvironment แล้ว)
 */
export function createSmsSender(
  env: NodeJS.ProcessEnv = process.env,
): SmsSender | null {
  const provider = env.SMS_PROVIDER?.trim() || 'console';
  if (provider === 'console') {
    return env.NODE_ENV === 'production' ? null : new ConsoleSmsSender();
  }
  if (provider === 'twilio') {
    const accountSid = env.TWILIO_ACCOUNT_SID?.trim();
    const authToken = env.TWILIO_AUTH_TOKEN?.trim();
    const from = env.TWILIO_FROM?.trim();
    if (!accountSid || !authToken || !from) return null;
    return new TwilioSmsSender({ accountSid, authToken, from });
  }
  if (provider === 'thaibulksms') {
    const apiKey = env.THAIBULKSMS_API_KEY?.trim();
    const apiSecret = env.THAIBULKSMS_API_SECRET?.trim();
    const sender = env.THAIBULKSMS_SENDER?.trim();
    if (!apiKey || !apiSecret || !sender) return null;
    const force =
      env.THAIBULKSMS_FORCE?.trim() === 'standard' ? 'standard' : 'corporate';
    return new ThaiBulkSmsSender({ apiKey, apiSecret, sender, force });
  }
  return null;
}

@Injectable()
export class SmsService {
  private readonly sender = createSmsSender();

  async sendOtp(phone: string, code: string): Promise<void> {
    if (!this.sender) {
      throw new ServiceUnavailableException(
        process.env.SMS_PROVIDER?.trim() === 'none'
          ? 'ขณะนี้เปิดให้ทดลองใช้เฉพาะทีมงาน กรุณาโทรติดต่อทีมงานเพื่อเรียกช่าง'
          : 'ยังไม่ได้ตั้งค่าผู้ให้บริการ SMS',
      );
    }
    try {
      await this.sender.send(phone, otpMessage(code));
    } catch {
      throw new ServiceUnavailableException(
        'ส่งรหัส OTP ไม่สำเร็จ กรุณาลองใหม่ภายหลัง',
      );
    }
  }
}
