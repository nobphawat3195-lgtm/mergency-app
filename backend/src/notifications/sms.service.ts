import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';

function toThaiE164(phone: string): string {
  if (phone.startsWith('+')) return phone;
  if (phone.startsWith('0')) return `+66${phone.slice(1)}`;
  return phone;
}

@Injectable()
export class SmsService {
  private readonly logger = new Logger(SmsService.name);

  async sendOtp(phone: string, code: string): Promise<void> {
    const provider = process.env.SMS_PROVIDER ?? 'console';
    if (provider === 'console' && process.env.NODE_ENV !== 'production') {
      this.logger.debug(`Development OTP for ${phone}: ${code}`);
      return;
    }

    if (provider !== 'twilio') {
      throw new ServiceUnavailableException('ยังไม่ได้ตั้งค่าผู้ให้บริการ SMS');
    }

    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const from = process.env.TWILIO_FROM;
    if (!accountSid || !authToken || !from) {
      throw new ServiceUnavailableException('การตั้งค่า SMS ไม่ครบถ้วน');
    }

    const body = new URLSearchParams({
      To: toThaiE164(phone),
      From: from,
      Body: `รหัส MechNow OTP ของคุณคือ ${code} ใช้ได้ 5 นาที ห้ามบอกรหัสนี้กับผู้อื่น`,
    });
    const response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${Buffer.from(`${accountSid}:${authToken}`).toString('base64')}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body,
      },
    );

    if (!response.ok) {
      this.logger.error(`SMS provider returned HTTP ${response.status}`);
      throw new ServiceUnavailableException(
        'ส่งรหัส OTP ไม่สำเร็จ กรุณาลองใหม่ภายหลัง',
      );
    }
  }
}
