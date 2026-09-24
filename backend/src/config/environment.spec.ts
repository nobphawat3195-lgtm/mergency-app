import { allowedCorsOrigins, validateEnvironment } from './environment';

describe('environment safety', () => {
  const previousOrigin = process.env.CORS_ORIGIN;

  afterEach(() => {
    if (previousOrigin === undefined) delete process.env.CORS_ORIGIN;
    else process.env.CORS_ORIGIN = previousOrigin;
  });

  it('parses an explicit CORS allow-list', () => {
    process.env.CORS_ORIGIN = 'https://app.example.com, https://admin.example.com';
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
});
