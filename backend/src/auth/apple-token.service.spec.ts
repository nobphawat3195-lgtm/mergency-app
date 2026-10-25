import { generateKeyPairSync, verify as cryptoVerify } from 'node:crypto';

import { AppleTokenService } from './apple-token.service';

const NOW = Date.parse('2026-10-25T10:00:00Z');

describe('AppleTokenService', () => {
  const saved = { ...process.env };
  const { privateKey, publicKey } = generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });
  let fetchMock: jest.Mock;
  let prisma: {
    appleToken: { upsert: jest.Mock; findUnique: jest.Mock; delete: jest.Mock };
  };
  let service: AppleTokenService;

  function configure() {
    process.env.APPLE_TEAM_ID = 'TEAM123456';
    process.env.APPLE_SIGNIN_KEY_ID = 'KEY1234567';
    // .env เก็บ PEM บรรทัดเดียว
    process.env.APPLE_SIGNIN_PRIVATE_KEY = (
      privateKey.export({ format: 'pem', type: 'pkcs8' }) as string
    ).replace(/\n/g, '\\n');
  }

  beforeEach(() => {
    delete process.env.APPLE_TEAM_ID;
    delete process.env.APPLE_SIGNIN_KEY_ID;
    delete process.env.APPLE_SIGNIN_PRIVATE_KEY;
    fetchMock = jest.fn();
    global.fetch = fetchMock as never;
    prisma = {
      appleToken: {
        upsert: jest.fn().mockResolvedValue({}),
        findUnique: jest.fn().mockResolvedValue({
          appleUserId: 'apple-1',
          clientId: 'com.fixgo.fixgoCustomer',
          refreshToken: 'refresh-1',
        }),
        delete: jest.fn().mockResolvedValue({}),
      },
    };
    service = new AppleTokenService(prisma as never);
  });

  afterEach(() => {
    process.env = { ...saved };
  });

  it('builds an ES256 client secret Apple can verify', () => {
    configure();
    const secret = service.clientSecret('com.fixgo.fixgoCustomer', NOW);
    const [header, claims, signature] = secret.split('.');
    expect(JSON.parse(Buffer.from(header, 'base64url').toString())).toEqual({
      alg: 'ES256',
      kid: 'KEY1234567',
    });
    expect(JSON.parse(Buffer.from(claims, 'base64url').toString())).toEqual({
      iss: 'TEAM123456',
      iat: NOW / 1000,
      exp: NOW / 1000 + 300,
      aud: 'https://appleid.apple.com',
      sub: 'com.fixgo.fixgoCustomer',
    });
    expect(
      cryptoVerify(
        'sha256',
        Buffer.from(`${header}.${claims}`),
        { key: publicKey, dsaEncoding: 'ieee-p1363' },
        Buffer.from(signature, 'base64url'),
      ),
    ).toBe(true);
  });

  it('does nothing without the Sign in with Apple key', async () => {
    await service.store('apple-1', 'com.fixgo.fixgoCustomer', 'code');
    expect(fetchMock).not.toHaveBeenCalled();
    expect(prisma.appleToken.upsert).not.toHaveBeenCalled();
  });

  it('exchanges the authorization code and keeps the refresh token', async () => {
    configure();
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ refresh_token: 'refresh-2' }),
    });
    await service.store('apple-1', 'com.fixgo.fixgoProvider', 'code-1');
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://appleid.apple.com/auth/token');
    const body = init.body as URLSearchParams;
    expect(body.get('code')).toBe('code-1');
    expect(body.get('client_id')).toBe('com.fixgo.fixgoProvider');
    expect(body.get('grant_type')).toBe('authorization_code');
    expect(prisma.appleToken.upsert).toHaveBeenCalledWith({
      where: { appleUserId: 'apple-1' },
      create: {
        appleUserId: 'apple-1',
        clientId: 'com.fixgo.fixgoProvider',
        refreshToken: 'refresh-2',
      },
      update: {
        clientId: 'com.fixgo.fixgoProvider',
        refreshToken: 'refresh-2',
      },
    });
  });

  it('revokes the stored token and forgets it', async () => {
    configure();
    fetchMock.mockResolvedValue({ ok: true });
    await service.revoke('apple-1');
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://appleid.apple.com/auth/revoke');
    const body = init.body as URLSearchParams;
    expect(body.get('token')).toBe('refresh-1');
    expect(body.get('token_type_hint')).toBe('refresh_token');
    expect(prisma.appleToken.delete).toHaveBeenCalledWith({
      where: { appleUserId: 'apple-1' },
    });
  });

  it('never throws from revoke, so account deletion still succeeds', async () => {
    configure();
    fetchMock.mockRejectedValue(new Error('network down'));
    await expect(service.revoke('apple-1')).resolves.toBeUndefined();
    expect(prisma.appleToken.delete).toHaveBeenCalled();
  });

  it('skips revoke when nothing was stored', async () => {
    configure();
    prisma.appleToken.findUnique.mockResolvedValue(null);
    await service.revoke('apple-1');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
