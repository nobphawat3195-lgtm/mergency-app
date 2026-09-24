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
    'PAYMENT_WEBHOOK_SECRET',
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

  return config;
}

export function allowedCorsOrigins(): string[] | true {
  const value = process.env.CORS_ORIGIN?.trim();
  if (!value || value === '*') return true;
  return value
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}
