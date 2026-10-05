import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

import { LineLoginService } from './line-login.service';

const NOW = Date.parse('2026-09-28T10:00:00Z');

describe('LineLoginService', () => {
  const saved = { ...process.env };
  let fetchMock: jest.Mock;
  let prisma: {
    customer: { upsert: jest.Mock; findUnique: jest.Mock };
    provider: { findUnique: jest.Mock };
  };
  let service: LineLoginService;
  const jwt = new JwtService({ secret: 'test-secret' });

  beforeEach(() => {
    process.env.LINE_LOGIN_CHANNEL_ID = '1234567890';
    process.env.LINE_LOGIN_CHANNEL_SECRET = 'channel-secret';
    process.env.PUBLIC_WEB_URL = 'https://fixgo.example';
    process.env.PUBLIC_FIXER_URL = 'https://fixer.fixgo.example';
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
      provider: { findUnique: jest.fn().mockResolvedValue(null) },
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
    const { url } = service.start('customer', NOW);
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
    const { url, cookie } = service.start('customer', NOW);
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
    const { cookie } = service.start('customer', NOW);
    await expect(
      service.callback({ code: 'c', state: 'forged' }, cookie, NOW),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('rejects a tampered state cookie', async () => {
    const { url, cookie } = service.start('customer', NOW);
    const tampered = cookie.replace(/\.[^.]+$/, '.AAAA');
    await expect(
      service.callback({ code: 'c', state: stateFrom(url) }, tampered, NOW),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects an expired ticket', async () => {
    const { url, cookie } = service.start('customer', NOW);
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
    const { url, cookie } = service.start('customer', NOW);
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

  describe('provider app', () => {
    async function providerTicket(sub = 'Uprovider') {
      const { url, cookie } = service.start('provider', NOW);
      lineResponds(sub);
      const redirect = await service.callback(
        { code: 'c', state: stateFrom(url) },
        cookie,
        NOW,
      );
      expect(
        redirect.startsWith('https://fixer.fixgo.example/?line_ticket='),
      ).toBe(true);
      return new URL(redirect).searchParams.get('line_ticket')!;
    }

    it('is disabled when the fixer web address is not configured', () => {
      expect(service.isEnabled('provider')).toBe(true);
      delete process.env.PUBLIC_FIXER_URL;
      expect(service.isEnabled('provider')).toBe(false);
      expect(service.isEnabled('customer')).toBe(true);
    });

    it('gives a new mechanic a pending token that carries the LINE user id', async () => {
      const ticket = await providerTicket();
      // ไม่สร้างบัญชีลูกค้าให้ช่าง
      expect(prisma.customer.upsert).not.toHaveBeenCalled();
      const session = await service.exchange(ticket, NOW + 1_000);
      expect(session.hasProfile).toBe(false);
      expect(jwt.verify(session.accessToken)).toMatchObject({
        sub: 'pending:line:Uprovider',
        role: 'PROVIDER',
        phone: '',
        lineUserId: 'Uprovider',
      });
    });

    it('logs a registered mechanic into the existing account', async () => {
      prisma.provider.findUnique.mockResolvedValue({
        id: 'provider-1',
        phone: '0812345678',
        deletedAt: null,
      });
      const ticket = await providerTicket();
      const session = await service.exchange(ticket, NOW + 1_000);
      expect(prisma.provider.findUnique).toHaveBeenCalledWith(
        expect.objectContaining({ where: { lineUserId: 'Uprovider' } }),
      );
      expect(session.hasProfile).toBe(true);
      const payload = jwt.verify(session.accessToken);
      expect(payload).toMatchObject({
        sub: 'provider-1',
        role: 'PROVIDER',
        phone: '0812345678',
      });
      expect(payload.lineUserId).toBeUndefined();
    });

    it('cannot switch the app by editing the signed state cookie', async () => {
      const { url, cookie } = service.start('customer', NOW);
      const forged = cookie.replace('.customer.', '.provider.');
      await expect(
        service.callback({ code: 'c', state: stateFrom(url) }, forged, NOW),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('sends failed mechanic logins back to the mechanic web app', () => {
      const { url, cookie } = service.start('provider', NOW);
      expect(
        service.failureRedirect(service.failureApp(stateFrom(url), cookie)),
      ).toBe('https://fixer.fixgo.example/?line_error=1');
      // คุกกี้หายก็ยังรู้จาก state ว่าเริ่มจากแอปช่าง
      expect(service.failureApp(stateFrom(url), undefined)).toBe('provider');
    });

    it('finishes a mechanic login without the cookie when the signed state is valid', async () => {
      // iPhone: เริ่มในเบราว์เซอร์ของแอป LINE แล้วกลับมา callback ใน Safari คุกกี้จึงหาย
      const { url } = service.start('provider', NOW);
      lineResponds('Uprovider');
      const redirect = await service.callback(
        { code: 'c', state: stateFrom(url) },
        undefined,
        NOW + 5_000,
      );
      expect(
        redirect.startsWith('https://fixer.fixgo.example/?line_ticket='),
      ).toBe(true);
      // nonce มาจาก state ที่ลงลายเซ็นไว้ ไม่ต้องพึ่งคุกกี้
      const verifyBody = fetchMock.mock.calls[1][1].body as URLSearchParams;
      expect(verifyBody.get('nonce')).toBe(
        new URL(url).searchParams.get('nonce'),
      );
      expect(prisma.customer.upsert).not.toHaveBeenCalled();
    });

    it('rejects a forged state without the cookie and still returns to the right app', async () => {
      const { url } = service.start('provider', NOW);
      const forged = stateFrom(url).replace(/\.[^.]+$/, '.AAAA');
      await expect(
        service.callback({ code: 'c', state: forged }, undefined, NOW),
      ).rejects.toBeInstanceOf(UnauthorizedException);
      expect(fetchMock).not.toHaveBeenCalled();
      // ลายเซ็นไม่ถูก อ่านแอปไม่ได้: กลับเว็บลูกค้า
      expect(service.failureApp(forged, undefined)).toBe('customer');
      // state ปลอมแต่คุกกี้ของแอปช่างลายเซ็นถูก: กลับเว็บช่าง
      const { cookie } = service.start('provider', NOW);
      expect(service.failureApp(forged, cookie)).toBe('provider');
    });

    it('rejects a state with the app switched even without the cookie', async () => {
      const { url } = service.start('customer', NOW);
      const switched = stateFrom(url).replace('.customer.', '.provider.');
      await expect(
        service.callback({ code: 'c', state: switched }, undefined, NOW),
      ).rejects.toBeInstanceOf(UnauthorizedException);
      expect(service.failureApp(switched, undefined)).toBe('customer');
    });
  });

  it('rejects an expired state without the cookie', async () => {
    const { url } = service.start('customer', NOW);
    await expect(
      service.callback(
        { code: 'c', state: stateFrom(url) },
        undefined,
        NOW + 11 * 60_000,
      ),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('accepts each state only once', async () => {
    const { url } = service.start('customer', NOW);
    lineResponds();
    await service.callback(
      { code: 'c', state: stateFrom(url) },
      undefined,
      NOW,
    );
    await expect(
      service.callback({ code: 'c', state: stateFrom(url) }, undefined, NOW),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
