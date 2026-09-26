import { BadRequestException } from '@nestjs/common';

import { UploadsService } from './uploads.service';

const STORAGE_ENV = {
  S3_BUCKET: 'fixgo-uploads',
  S3_PUBLIC_BASE_URL: 'https://cdn.fixgo.test/',
  S3_ACCESS_KEY_ID: 'test-key',
  S3_SECRET_ACCESS_KEY: 'test-secret',
  S3_REGION: 'auto',
};

function withEnv<T>(env: Record<string, string | undefined>, run: () => T): T {
  const previous = { ...process.env };
  Object.assign(process.env, env);
  try {
    return run();
  } finally {
    process.env = previous;
  }
}

const file = '3f2b8c1e-9a4d-4e21-8f00-1234567890ab.jpg';

describe('UploadsService.assertOwnedUploads', () => {
  const service = withEnv(STORAGE_ENV, () => new UploadsService());

  it('accepts files this user uploaded through presign', () => {
    expect(() =>
      service.assertOwnedUploads(
        [`https://cdn.fixgo.test/orders/cus_1/${file}`],
        'cus_1',
        'ORDER',
      ),
    ).not.toThrow();
    expect(() =>
      service.assertOwnedUploads(
        [`https://cdn.fixgo.test/provider-tools/pending:0812345678/${file}`],
        'pending:0812345678',
        'PROVIDER_TOOL',
      ),
    ).not.toThrow();
  });

  it.each([
    ['external host', `https://evil.example/orders/cus_1/${file}`],
    ['another user', `https://cdn.fixgo.test/orders/cus_2/${file}`],
    ['another scope', `https://cdn.fixgo.test/inspections/cus_1/${file}`],
    ['path traversal', `https://cdn.fixgo.test/orders/cus_1/../cus_2/${file}`],
    ['non-uuid name', 'https://cdn.fixgo.test/orders/cus_1/avatar.jpg'],
    ['query tricks', `https://cdn.fixgo.test/orders/cus_1/${file}?x=1`],
    [
      'host prefix trick',
      `https://cdn.fixgo.test.evil.example/orders/cus_1/${file}`,
    ],
  ])('rejects %s', (_label, url) => {
    expect(() => service.assertOwnedUploads([url], 'cus_1', 'ORDER')).toThrow(
      BadRequestException,
    );
  });

  it('skips the check when storage is not configured (local development)', () => {
    const dev = withEnv(
      { S3_BUCKET: undefined, S3_PUBLIC_BASE_URL: undefined },
      () => {
        delete process.env.S3_BUCKET;
        delete process.env.S3_PUBLIC_BASE_URL;
        return new UploadsService();
      },
    );
    expect(() =>
      dev.assertOwnedUploads(['http://localhost/x.jpg'], 'cus_1', 'ORDER'),
    ).not.toThrow();
  });
});
