import { ServiceUnavailableException } from '@nestjs/common';

import {
  createSmsSender,
  otpMessage,
  SmsService,
  ThaiBulkSmsSender,
  toThaiE164,
  TwilioSmsSender,
} from './sms.service';

function response(status: number, body: unknown = {}) {
  return { ok: status < 300, status, json: async () => body };
}

type Call = [string, { headers: Record<string, string>; body: string }];

describe('ThaiBulkSmsSender', () => {
  const config = {
    apiKey: 'key',
    apiSecret: 'secret',
    sender: 'FixGo',
    force: 'corporate' as const,
  };

  it('posts a form with basic auth to the v2 endpoint', async () => {
    const fetch = jest
      .fn()
      .mockResolvedValue(
        response(201, { phone_number_list: [{ number: '66812345678' }] }),
      );
    await new ThaiBulkSmsSender(config, fetch).send(
      '0812345678',
      otpMessage('123456'),
    );

    const [url, init] = fetch.mock.calls[0] as Call;
    expect(url).toBe('https://api-v2.thaibulksms.com/sms');
    expect(init.headers.Authorization).toBe(
      `Basic ${Buffer.from('key:secret').toString('base64')}`,
    );
    const form = new URLSearchParams(init.body);
    expect(form.get('msisdn')).toBe('0812345678');
    expect(form.get('sender')).toBe('FixGo');
    expect(form.get('force')).toBe('corporate');
    expect(form.get('message')).toContain('123456');
  });

  it('fails on HTTP errors', async () => {
    const fetch = jest
      .fn()
      .mockResolvedValue(
        response(401, { error: { code: 401, name: 'UNAUTHORIZED' } }),
      );
    await expect(
      new ThaiBulkSmsSender(config, fetch).send('0812345678', 'x'),
    ).rejects.toThrow('401');
  });

  it('fails when the number is listed as bad even with HTTP 201', async () => {
    const fetch = jest
      .fn()
      .mockResolvedValue(
        response(201, { bad_phone_number_list: [{ number: '0812' }] }),
      );
    await expect(
      new ThaiBulkSmsSender(config, fetch).send('0812', 'x'),
    ).rejects.toThrow('rejected');
  });
});

describe('TwilioSmsSender', () => {
  it('sends to the E.164 number', async () => {
    const fetch = jest.fn().mockResolvedValue(response(201));
    await new TwilioSmsSender(
      { accountSid: 'AC1', authToken: 't', from: '+100' },
      fetch,
    ).send('0812345678', 'hello');
    const [url, init] = fetch.mock.calls[0] as Call;
    expect(url).toContain('/Accounts/AC1/Messages.json');
    expect(new URLSearchParams(init.body).get('To')).toBe('+66812345678');
  });
});

describe('createSmsSender', () => {
  it('picks the provider from SMS_PROVIDER', () => {
    expect(createSmsSender({})?.name).toBe('console');
    expect(
      createSmsSender({
        SMS_PROVIDER: 'thaibulksms',
        THAIBULKSMS_API_KEY: 'k',
        THAIBULKSMS_API_SECRET: 's',
        THAIBULKSMS_SENDER: 'FixGo',
      })?.name,
    ).toBe('thaibulksms');
  });

  it('never logs OTPs to the console in production', () => {
    expect(
      createSmsSender({ NODE_ENV: 'production', SMS_PROVIDER: 'console' }),
    ).toBeNull();
  });

  it('returns null when credentials are incomplete', () => {
    expect(createSmsSender({ SMS_PROVIDER: 'thaibulksms' })).toBeNull();
    expect(createSmsSender({ SMS_PROVIDER: 'unknown' })).toBeNull();
  });
});

describe('SmsService', () => {
  it('turns provider failures into a 503 the app can show', async () => {
    const previous = process.env.SMS_PROVIDER;
    process.env.SMS_PROVIDER = 'unknown';
    const service = new SmsService();
    process.env.SMS_PROVIDER = previous;
    await expect(
      service.sendOtp('0812345678', '123456'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('formats Thai numbers as E.164', () => {
    expect(toThaiE164('0812345678')).toBe('+66812345678');
    expect(toThaiE164('+66812345678')).toBe('+66812345678');
  });
});
