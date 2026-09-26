import {
  allowedCorsOrigins,
  reviewLoginCodeFor,
  validateEnvironment,
} from './environment';

describe('environment safety', () => {
  const previousOrigin = process.env.CORS_ORIGIN;

  afterEach(() => {
    if (previousOrigin === undefined) delete process.env.CORS_ORIGIN;
    else process.env.CORS_ORIGIN = previousOrigin;
  });

  it('parses an explicit CORS allow-list', () => {
    process.env.CORS_ORIGIN =
      'https://app.example.com, https://admin.example.com';
    expect(allowedCorsOrigins()).toEqual([
      'https://app.example.com',
      'https://admin.example.com',
    ]);
  });

  it('rejects placeholder production secrets', () => {
    expect(() =>
      validateEnvironment({
        NODE_ENV: 'production',
        DATABASE_URL: 'postgresql://example',
        JWT_SECRET: 'change-me-in-production',
      }),
    ).toThrow('JWT_SECRET');
  });

  describe('review login', () => {
    const saved = {
      phones: process.env.REVIEW_LOGIN_PHONES,
      code: process.env.REVIEW_LOGIN_CODE,
    };
    afterEach(() => {
      process.env.REVIEW_LOGIN_PHONES = saved.phones;
      process.env.REVIEW_LOGIN_CODE = saved.code;
      if (saved.phones === undefined) delete process.env.REVIEW_LOGIN_PHONES;
      if (saved.code === undefined) delete process.env.REVIEW_LOGIN_CODE;
    });

    it('returns the fixed code only for listed phones', () => {
      process.env.REVIEW_LOGIN_PHONES = '0800000001, 0800000002';
      process.env.REVIEW_LOGIN_CODE = '246810';
      expect(reviewLoginCodeFor('0800000002')).toBe('246810');
      expect(reviewLoginCodeFor('0812345678')).toBeNull();
    });

    it('is disabled when not configured or the code is invalid', () => {
      delete process.env.REVIEW_LOGIN_PHONES;
      process.env.REVIEW_LOGIN_CODE = '246810';
      expect(reviewLoginCodeFor('0800000001')).toBeNull();
      process.env.REVIEW_LOGIN_PHONES = '0800000001';
      process.env.REVIEW_LOGIN_CODE = '12';
      expect(reviewLoginCodeFor('0800000001')).toBeNull();
    });
  });

  describe('payment provider', () => {
    const base = {
      NODE_ENV: 'production',
      DATABASE_URL: 'postgresql://example',
      JWT_SECRET: 'real-jwt',
      OTP_SECRET: 'real-otp',
      S3_BUCKET: 'b',
      S3_ACCESS_KEY_ID: 'k',
      S3_SECRET_ACCESS_KEY: 's',
      S3_PUBLIC_BASE_URL: 'https://cdn.example.com',
      CORS_ORIGIN: 'https://app.example.com',
      SMS_PROVIDER: 'twilio',
      TWILIO_ACCOUNT_SID: 'a',
      TWILIO_AUTH_TOKEN: 't',
      TWILIO_FROM: '+1',
    };

    it('requires Stripe keys when PAYMENT_PROVIDER=stripe', () => {
      expect(() =>
        validateEnvironment({ ...base, PAYMENT_PROVIDER: 'stripe' }),
      ).toThrow('STRIPE_SECRET_KEY');
      expect(() =>
        validateEnvironment({
          ...base,
          PAYMENT_PROVIDER: 'stripe',
          STRIPE_SECRET_KEY: 'sk_test_x',
          STRIPE_WEBHOOK_SECRET: 'whsec_x',
          STRIPE_BILLING_EMAIL: 'pay@fixgo.test',
        }),
      ).not.toThrow();
    });

    it('requires the PromptPay id and payee name for manual transfers', () => {
      expect(() =>
        validateEnvironment({ ...base, PAYMENT_PROVIDER: 'promptpay_manual' }),
      ).toThrow('PROMPTPAY_ID');
      expect(() =>
        validateEnvironment({
          ...base,
          PAYMENT_PROVIDER: 'promptpay_manual',
          PROMPTPAY_ID: '0812345678',
          PROMPTPAY_NAME: 'FixGo',
        }),
      ).not.toThrow();
    });

    it('still requires the HMAC webhook secret for the stub gateway', () => {
      expect(() => validateEnvironment(base)).toThrow('PAYMENT_WEBHOOK_SECRET');
    });
  });

  describe('sms and push providers', () => {
    const base = {
      NODE_ENV: 'production',
      DATABASE_URL: 'postgresql://example',
      JWT_SECRET: 'real-jwt',
      OTP_SECRET: 'real-otp',
      PAYMENT_WEBHOOK_SECRET: 'real-hook',
      S3_BUCKET: 'b',
      S3_ACCESS_KEY_ID: 'k',
      S3_SECRET_ACCESS_KEY: 's',
      S3_PUBLIC_BASE_URL: 'https://cdn.example.com',
      CORS_ORIGIN: 'https://app.example.com',
    };

    it('allows SMS_PROVIDER=none only with team test phones', () => {
      expect(() =>
        validateEnvironment({ ...base, SMS_PROVIDER: 'none' }),
      ).toThrow('REVIEW_LOGIN_PHONES');
      expect(() =>
        validateEnvironment({
          ...base,
          SMS_PROVIDER: 'none',
          REVIEW_LOGIN_PHONES: '0811111111',
          REVIEW_LOGIN_CODE: '482913',
        }),
      ).not.toThrow();
    });

    it('rejects an invalid COMMISSION_RATE at startup', () => {
      const ok = {
        ...base,
        SMS_PROVIDER: 'twilio',
        TWILIO_ACCOUNT_SID: 'a',
        TWILIO_AUTH_TOKEN: 't',
        TWILIO_FROM: '+1',
      };
      expect(() =>
        validateEnvironment({ ...ok, COMMISSION_RATE: '35' }),
      ).toThrow('COMMISSION_RATE');
      expect(() =>
        validateEnvironment({ ...ok, COMMISSION_RATE: '0.3' }),
      ).not.toThrow();
    });

    it('rejects console SMS in production', () => {
      expect(() =>
        validateEnvironment({ ...base, SMS_PROVIDER: 'console' }),
      ).toThrow('SMS_PROVIDER');
    });

    it('accepts ThaiBulkSMS with its credentials', () => {
      expect(() =>
        validateEnvironment({ ...base, SMS_PROVIDER: 'thaibulksms' }),
      ).toThrow('THAIBULKSMS_API_KEY');
      expect(() =>
        validateEnvironment({
          ...base,
          SMS_PROVIDER: 'thaibulksms',
          THAIBULKSMS_API_KEY: 'k',
          THAIBULKSMS_API_SECRET: 's',
          THAIBULKSMS_SENDER: 'FixGo',
        }),
      ).not.toThrow();
    });

    it('lets STORAGE_PROVIDER=local run without R2/S3 keys', () => {
      const noS3 = {
        NODE_ENV: 'production',
        DATABASE_URL: 'postgresql://example',
        JWT_SECRET: 'real-jwt',
        OTP_SECRET: 'real-otp',
        PAYMENT_WEBHOOK_SECRET: 'real-hook',
        CORS_ORIGIN: 'https://app.example.com',
        SMS_PROVIDER: 'twilio',
        TWILIO_ACCOUNT_SID: 'a',
        TWILIO_AUTH_TOKEN: 't',
        TWILIO_FROM: '+1',
      };
      expect(() => validateEnvironment(noS3)).toThrow('S3_BUCKET');
      expect(() =>
        validateEnvironment({ ...noS3, STORAGE_PROVIDER: 'local' }),
      ).toThrow('API_DOMAIN');
      expect(() =>
        validateEnvironment({
          ...noS3,
          STORAGE_PROVIDER: 'local',
          API_DOMAIN: 'api.example.com',
        }),
      ).not.toThrow();
    });

    it('requires FCM credentials when push is enabled', () => {
      const withSms = {
        ...base,
        SMS_PROVIDER: 'twilio',
        TWILIO_ACCOUNT_SID: 'a',
        TWILIO_AUTH_TOKEN: 't',
        TWILIO_FROM: '+1',
      };
      expect(() =>
        validateEnvironment({ ...withSms, PUSH_PROVIDER: 'fcm' }),
      ).toThrow('FCM_PROJECT_ID');
      expect(() => validateEnvironment(withSms)).not.toThrow();
    });
  });
});
