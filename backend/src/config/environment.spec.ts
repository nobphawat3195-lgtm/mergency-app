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

    it('still requires the HMAC webhook secret for the stub gateway', () => {
      expect(() => validateEnvironment(base)).toThrow('PAYMENT_WEBHOOK_SECRET');
    });
  });
});
