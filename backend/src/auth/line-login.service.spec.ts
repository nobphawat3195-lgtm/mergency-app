import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

import { LineLoginService } from './line-login.service';

const NOW = Date.parse('2026-09-28T10:00:00Z');

describe('LineLoginService', () => {
  const saved = { ...process.env };
  let fetchMock: jest.Mock;
  let prisma: {
    customer: { upsert: jest.Mock; findUnique: jest.Mock };
  };
  let service: LineLoginService;
  const jwt = new JwtService({ secret: 'test-secret' });

  beforeEach(() => {
    process.env.LINE_LOGIN_CHANNEL_ID = '1234567890';
    process.env.LINE_LOGIN_CHANNEL_SECRET = 'channel-secret';
    process.env.PUBLIC_WEB_URL = 'https://fixgo.example';
    process.env.PUBLIC_API_URL = 'https://api.fixgo.example';
    const customer = {
      id: '11111111-1111-4111-8111-111111111111',
      phone: null,
      deletedAt: null,
    };
    prisma = {
      customer: {
        upsert: jest.fn().mockResolvedValue(customer),
        findUnique: jest.fn().mockResolvedValue(customer),
      },
    };
    service = new LineLoginService(prisma as never, jwt);
    fetchMock = jest.fn();
    global.fetch = fetchMock as never;
  });

  afterEach(() => {
    process.env = { ...saved };
  });

  function lineResponds(sub = 'Uline-user') {
    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id_token: 'id.token.value' }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ sub, name: 'คุณเอ' }),
      });
  }

  function stateFrom(url: string) {
    return new URL(url).searchParams.get('state')!;
  }

  it('is disabled until both credentials are configured', () => {
    expect(service.isEnabled()).toBe(true);
    delete process.env.LINE_LOGIN_CHANNEL_SECRET;
    expect(service.isEnabled()).toBe(false);
  });

  it('sends the user to LINE with state, nonce and the API callback', () => {
    const { url } = service.start(NOW);
    const params = new URL(url).searchParams;
    expect(
      url.startsWith('https://access.line.me/oauth2/v2.1/authorize?'),
    ).toBe(true);
    expect(params.get('client_id')).toBe('1234567890');
    expect(params.get('redirect_uri')).toBe(
      'https://api.fixgo.example/api/auth/line/callback',
    );
    expect(params.get('scope')).toBe('profile openid');
    expect(params.get('nonce')).toBeTruthy();
  });

  it('logs in with a one-time ticket after LINE verifies the id_token', async () => {
    const { url, cookie } = service.start(NOW);
    lineResponds();
    const redirect = await service.callback(
      { code: 'auth-code', state: stateFrom(url) },
      cookie,
      NOW + 5_000,
    );
    expect(redirect.startsWith('https://fixgo.example/?line_ticket=')).toBe(
      true,
    );
    // ส่ง nonce ที่สร้างตอน start ไปให้ LINE ตรวจ
    const verifyBody = fetchMock.mock.calls[1][1].body as URLSearchParams;
    expect(verifyBody.get('nonce')).toBe(
      new URL(url).searchParams.get('nonce'),
    );
    expect(prisma.customer.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ where: { lineUserId: 'Uline-user' } }),
    );

    const ticket = new URL(redirect).searchParams.get('line_ticket')!;
    const session = await service.exchange(ticket, NOW + 10_000);
    const payload = jwt.verify(session.accessToken);
    expect(payload).toMatchObject({
      sub: '11111111-1111-4111-8111-111111111111',
      role: 'CUSTOMER',
    });

    await expect(service.exchange(ticket, NOW + 11_000)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects a callback whose state does not match the cookie', async () => {
    const { cookie } = service.start(NOW);
    await expect(
      service.callback({ code: 'c', state: 'forged' }, cookie, NOW),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('rejects a tampered state cookie', async () => {
    const { url, cookie } = service.start(NOW);
    const tampered = cookie.replace(/\.[^.]+$/, '.AAAA');
    await expect(
      service.callback({ code: 'c', state: stateFrom(url) }, tampered, NOW),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects an expired ticket', async () => {
    const { url, cookie } = service.start(NOW);
    lineResponds();
    const redirect = await service.callback(
      { code: 'c', state: stateFrom(url) },
      cookie,
      NOW,
    );
    const ticket = new URL(redirect).searchParams.get('line_ticket')!;
    await expect(service.exchange(ticket, NOW + 61_000)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('does not log in when LINE rejects the id_token', async () => {
    const { url, cookie } = service.start(NOW);
    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id_token: 'id.token.value' }),
      })
      .mockResolvedValueOnce({ ok: false, status: 400 });
    await expect(
      service.callback({ code: 'c', state: stateFrom(url) }, cookie, NOW),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.customer.upsert).not.toHaveBeenCalled();
  });
});
