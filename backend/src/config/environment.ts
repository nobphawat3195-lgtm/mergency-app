const PLACEHOLDER_VALUES = new Set([
  'change-me-in-production',
  'dev-jwt-secret',
  'dev-otp-secret',
]);

export function isProduction(): boolean {
  return process.env.NODE_ENV === 'production';
}

export function readSecret(
  name: 'JWT_SECRET' | 'OTP_SECRET' | 'PAYMENT_WEBHOOK_SECRET',
  developmentFallback?: string,
): string {
  const value = process.env[name]?.trim();

  if (value && !PLACEHOLDER_VALUES.has(value)) return value;
  if (!isProduction() && developmentFallback) return developmentFallback;

  throw new Error(
    `${name} is required and must not use a placeholder in production`,
  );
}

export function validateEnvironment(
  config: Record<string, unknown>,
): Record<string, unknown> {
  if (config.NODE_ENV !== 'production') return config;

  for (const name of [
    'DATABASE_URL',
    'JWT_SECRET',
    'OTP_SECRET',
    'S3_BUCKET',
    'S3_ACCESS_KEY_ID',
    'S3_SECRET_ACCESS_KEY',
    'S3_PUBLIC_BASE_URL',
  ] as const) {
    const value = String(config[name] ?? '').trim();
    if (!value || PLACEHOLDER_VALUES.has(value)) {
      throw new Error(
        `${name} is required and must not use a placeholder in production`,
      );
    }
  }

  const corsOrigin = String(config.CORS_ORIGIN ?? '').trim();
  if (!corsOrigin || corsOrigin === '*') {
    throw new Error('CORS_ORIGIN must be an explicit allow-list in production');
  }

  if (String(config.SMS_PROVIDER ?? '') !== 'twilio') {
    throw new Error('SMS_PROVIDER must be twilio in production');
  }
  for (const name of [
    'TWILIO_ACCOUNT_SID',
    'TWILIO_AUTH_TOKEN',
    'TWILIO_FROM',
  ] as const) {
    if (!String(config[name] ?? '').trim()) {
      throw new Error(`${name} is required in production`);
    }
  }

  const paymentProvider = String(config.PAYMENT_PROVIDER ?? 'stub').trim();
  if (paymentProvider === 'stripe') {
    for (const name of [
      'STRIPE_SECRET_KEY',
      'STRIPE_WEBHOOK_SECRET',
    ] as const) {
      if (!String(config[name] ?? '').trim()) {
        throw new Error(`${name} is required when PAYMENT_PROVIDER=stripe`);
      }
    }
    if (
      !String(config.STRIPE_BILLING_EMAIL ?? '').trim() &&
      !String(config.LEGAL_CONTACT_EMAIL ?? '').trim()
    ) {
      throw new Error(
        'STRIPE_BILLING_EMAIL (or LEGAL_CONTACT_EMAIL) is required for Stripe PromptPay',
      );
    }
  } else {
    // gateway stub ปิดพร้อมเพย์ใน production อยู่แล้ว แต่ webhook HMAC เดิมยังต้องมี secret จริง
    const secret = String(config.PAYMENT_WEBHOOK_SECRET ?? '').trim();
    if (!secret || PLACEHOLDER_VALUES.has(secret)) {
      throw new Error(
        'PAYMENT_WEBHOOK_SECRET is required and must not use a placeholder in production',
      );
    }
  }

  const reviewPhones = String(config.REVIEW_LOGIN_PHONES ?? '').trim();
  if (reviewPhones && !/^\d{6}$/.test(String(config.REVIEW_LOGIN_CODE ?? ''))) {
    throw new Error(
      'REVIEW_LOGIN_CODE must be 6 digits when REVIEW_LOGIN_PHONES is set',
    );
  }

  return config;
}

/**
 * บัญชีทดสอบสำหรับทีมรีวิวของ Apple/Google ซึ่งรับ SMS ไม่ได้
 *
 * ตั้ง REVIEW_LOGIN_PHONES (คั่นด้วยจุลภาค) และ REVIEW_LOGIN_CODE (6 หลัก) แล้วเบอร์เหล่านี้
 * จะใช้รหัสตายตัวโดยไม่ส่ง SMS ใช้เฉพาะเบอร์ที่ไม่มีเจ้าของจริง และลบออกหลังรีวิวผ่าน
 */
export function reviewLoginCodeFor(phone: string): string | null {
  const phones = (process.env.REVIEW_LOGIN_PHONES ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  const code = process.env.REVIEW_LOGIN_CODE?.trim() ?? '';
  if (!phones.includes(phone) || !/^\d{6}$/.test(code)) return null;
  return code;
}

export function allowedCorsOrigins(): string[] | true {
  const value = process.env.CORS_ORIGIN?.trim();
  if (!value || value === '*') return true;
  return value
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}
