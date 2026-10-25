import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  createHash,
  generateKeyPairSync,
  KeyObject,
  sign as cryptoSign,
} from 'node:crypto';

import { AppleLoginService, appleClientId } from './apple-login.service';

const NOW = Date.parse('2026-10-25T10:00:00Z');
const NOW_S = Math.floor(NOW / 1000);
const NONCE = 'raw-nonce-from-app';

describe('AppleLoginService', () => {
  const jwt = new JwtService({ secret: 'test-secret' });
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  const otherKey = generateKeyPairSync('rsa', { modulusLength: 2048 });
  let fetchMock: jest.Mock;
  let tokens: { store: jest.Mock };
  let prisma: {
    customer: { upsert: jest.Mock };
    provider: { findUnique: jest.Mock };
  };
  let service: AppleLoginService;

  function jwks(...entries: [string, KeyObject][]) {
    return {
      ok: true,
      json: async () => ({
        keys: entries.map(([kid, key]) => ({
          ...key.export({ format: 'jwk' }),
          kid,
          alg: 'RS256',
          use: 'sig',
        })),
      }),
    };
  }

  function token(
    claims: Record<string, unknown> = {},
    { kid = 'k1', key = privateKey }: { kid?: string; key?: KeyObject } = {},
  ) {
    const header = Buffer.from(JSON.stringify({ alg: 'RS256', kid })).toString(
      'base64url',
    );
    const body = Buffer.from(
      JSON.stringify({
        iss: 'https://appleid.apple.com',
        aud: 'com.fixgo.fixgoCustomer',
        sub: '001234.apple-user',
        iat: NOW_S - 10,
        exp: NOW_S + 600,
        nonce: createHash('sha256').update(NONCE).digest('hex'),
        ...claims,
      }),
    ).toString('base64url');
    const signature = cryptoSign(
      'RSA-SHA256',
      Buffer.from(`${header}.${body}`),
      key,
    ).toString('base64url');
    return `${header}.${body}.${signature}`;
  }

  beforeEach(() => {
    fetchMock = jest.fn().mockResolvedValue(jwks(['k1', publicKey]));
    global.fetch = fetchMock as never;
    tokens = { store: jest.fn().mockResolvedValue(undefined) };
    prisma = {
      customer: {
        upsert: jest.fn().mockResolvedValue({
          id: 'customer-1',
          phone: null,
          deletedAt: null,
        }),
      },
      provider: { findUnique: jest.fn().mockResolvedValue(null) },
    };
    service = new AppleLoginService(prisma as never, jwt, tokens as never);
  });

  it('signs a customer in and keys the account on the Apple user id', async () => {
    const session = await service.signIn(
      {
        app: 'customer',
        identityToken: token(),
        nonce: NONCE,
        fullName: '  สมชาย ใจดี ',
      },
      NOW,
    );
    expect(prisma.customer.upsert).toHaveBeenCalledWith({
      where: { appleUserId: '001234.apple-user' },
      create: { appleUserId: '001234.apple-user', name: 'สมชาย ใจดี' },
      update: {},
    });
    expect(session.hasProfile).toBe(true);
    expect(jwt.decode(session.accessToken)).toMatchObject({
      sub: 'customer-1',
      role: 'CUSTOMER',
    });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://appleid.apple.com/auth/keys',
    );
  });

  it('gives a new mechanic a pending token carrying the Apple user id', async () => {
    const session = await service.signIn(
      {
        app: 'provider',
        identityToken: token({ aud: 'com.fixgo.fixgoProvider' }),
        nonce: NONCE,
      },
      NOW,
    );
    expect(session.hasProfile).toBe(false);
    expect(jwt.decode(session.accessToken)).toMatchObject({
      sub: 'pending:apple:001234.apple-user',
      role: 'PROVIDER',
      appleUserId: '001234.apple-user',
    });
    expect(prisma.customer.upsert).not.toHaveBeenCalled();
  });

  it('signs an existing mechanic into their account', async () => {
    prisma.provider.findUnique.mockResolvedValue({
      id: 'provider-1',
      phone: '0812345678',
      deletedAt: null,
    });
    const session = await service.signIn(
      {
        app: 'provider',
        identityToken: token({ aud: 'com.fixgo.fixgoProvider' }),
        nonce: NONCE,
      },
      NOW,
    );
    expect(session).toMatchObject({ hasProfile: true, userId: 'provider-1' });
  });

  it('rejects a customer-app token sent as the mechanic app (wrong audience)', async () => {
    await expect(
      service.signIn(
        { app: 'provider', identityToken: token(), nonce: NONCE },
        NOW,
      ),
    ).rejects.toThrow(UnauthorizedException);
  });

  it.each([
    ['wrong issuer', { iss: 'https://evil.example' }],
    ['expired', { exp: NOW_S - 120 }],
    ['nonce mismatch', { nonce: 'deadbeef' }],
    ['missing nonce', { nonce: undefined }],
    ['missing sub', { sub: undefined }],
  ])('rejects a token with %s', async (_label, claims) => {
    await expect(
      service.signIn(
        { app: 'customer', identityToken: token(claims), nonce: NONCE },
        NOW,
      ),
    ).rejects.toThrow(UnauthorizedException);
    expect(prisma.customer.upsert).not.toHaveBeenCalled();
  });

  it('rejects a token signed by another key', async () => {
    await expect(
      service.signIn(
        {
          app: 'customer',
          identityToken: token({}, { key: otherKey.privateKey }),
          nonce: NONCE,
        },
        NOW,
      ),
    ).rejects.toThrow('ลายเซ็นของ Apple ไม่ถูกต้อง');
  });

  it('rejects a replayed token', async () => {
    const identityToken = token();
    await service.signIn({ app: 'customer', identityToken, nonce: NONCE }, NOW);
    await expect(
      service.signIn({ app: 'customer', identityToken, nonce: NONCE }, NOW),
    ).rejects.toThrow('ถูกใช้ไปแล้ว');
  });

  it('reloads Apple keys when it sees an unknown key id', async () => {
    await service.signIn(
      { app: 'customer', identityToken: token(), nonce: NONCE },
      NOW,
    );
    fetchMock.mockResolvedValueOnce(
      jwks(['k1', publicKey], ['k2', otherKey.publicKey]),
    );
    await service.signIn(
      {
        app: 'customer',
        identityToken: token({}, { kid: 'k2', key: otherKey.privateKey }),
        nonce: NONCE,
      },
      NOW,
    );
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('stores the refresh token but still signs in when Apple refuses the code', async () => {
    tokens.store.mockRejectedValue(new Error('token 400'));
    const session = await service.signIn(
      {
        app: 'customer',
        identityToken: token(),
        nonce: NONCE,
        authorizationCode: 'code-1',
      },
      NOW,
    );
    expect(tokens.store).toHaveBeenCalledWith(
      '001234.apple-user',
      'com.fixgo.fixgoCustomer',
      'code-1',
    );
    expect(session.hasProfile).toBe(true);
  });

  it('refuses a deleted customer', async () => {
    prisma.customer.upsert.mockResolvedValue({
      id: 'customer-1',
      phone: null,
      deletedAt: new Date(),
    });
    await expect(
      service.signIn(
        { app: 'customer', identityToken: token(), nonce: NONCE },
        NOW,
      ),
    ).rejects.toThrow('บัญชีนี้ถูกลบแล้ว');
  });

  it('uses configured bundle ids when set', () => {
    expect(
      appleClientId('provider', { APPLE_PROVIDER_CLIENT_ID: 'th.fixer' }),
    ).toBe('th.fixer');
    expect(appleClientId('customer', {})).toBe('com.fixgo.fixgoCustomer');
  });
});
