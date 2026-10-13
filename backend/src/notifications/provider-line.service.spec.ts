import {
  offerLineText,
  ProviderLineConfig,
  ProviderLineService,
  providerLineAddFriendUrl,
  readProviderLineConfig,
} from './provider-line.service';
import { dispatchOfferTimeoutMs } from '../common/constants';

const CONFIG: ProviderLineConfig = {
  enabled: true,
  token: 'line-token',
  fixerUrl: 'https://fixer.fixgo.example',
  addFriendUrl: 'https://lin.ee/abc',
};

const ORDER = {
  serviceName: 'จั๊มแบต',
  area: 'บางนา, กรุงเทพมหานคร',
  priceSatang: 50000,
};

function setup(
  config: Partial<ProviderLineConfig> = {},
  linked = [{ id: 'p1', lineUserId: 'Uline1' }],
) {
  const prisma = {
    provider: { findMany: jest.fn().mockResolvedValue(linked) },
  };
  const fetchImpl = jest.fn().mockResolvedValue({ ok: true, status: 200 });
  const service = new ProviderLineService(
    prisma as never,
    { ...CONFIG, ...config },
    fetchImpl,
  );
  return { service, prisma, fetchImpl };
}

function sentBody(fetchImpl: jest.Mock, call = 0) {
  return JSON.parse(fetchImpl.mock.calls[call][1].body);
}

describe('ProviderLineService', () => {
  it('pushes the new job with price, area, time limit and an open button', async () => {
    const { service, prisma, fetchImpl } = setup();

    await service.offer(['p1', 'p2'], ORDER, 180_000);

    // ช่างที่ไม่มี lineUserId ถูกกรองออกตั้งแต่ query
    expect(prisma.provider.findMany).toHaveBeenCalledWith({
      where: { id: { in: ['p1', 'p2'] }, lineUserId: { not: null } },
      select: { id: true, lineUserId: true },
    });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe('https://api.line.me/v2/bot/message/push');
    expect(init.headers.Authorization).toBe('Bearer line-token');
    const text =
      '🔔 มีงานใหม่ใกล้คุณ\nจั๊มแบต · บางนา, กรุงเทพมหานคร\nราคาประเมิน ฿500\nกดรับภายใน 3 นาที';
    expect(sentBody(fetchImpl)).toEqual({
      to: 'Uline1',
      messages: [
        {
          type: 'template',
          altText: text,
          template: {
            type: 'buttons',
            text,
            actions: [
              {
                type: 'uri',
                label: 'เปิดรับงาน',
                uri: 'https://fixer.fixgo.example/',
              },
            ],
          },
        },
      ],
    });
  });

  it('never tells the mechanic more time than they have', () => {
    expect(offerLineText(ORDER, 90_000)).toContain('กดรับภายใน 1 นาที');
    expect(offerLineText(ORDER, 45_000)).toContain('กดรับภายใน 45 วินาที');
    expect(offerLineText({ ...ORDER, area: null }, 90_000)).toContain(
      '\nจั๊มแบต\n',
    );
  });

  it('keeps the button text within the LINE limit', async () => {
    const { service, fetchImpl } = setup();
    await service.offer(
      ['p1'],
      { ...ORDER, serviceName: 'ซ่อม'.repeat(60) },
      90_000,
    );
    const message = sentBody(fetchImpl).messages[0];
    expect(message.template.text.length).toBeLessThanOrEqual(160);
    expect(message.altText.length).toBeLessThanOrEqual(400);
  });

  it('sends plain text when the fixer web address is not set', async () => {
    const { service, fetchImpl } = setup({ fixerUrl: null });
    await service.offer(['p1'], ORDER, 90_000);
    expect(sentBody(fetchImpl).messages[0].type).toBe('text');
  });

  it('tells the assigned mechanic about quote answers and cancellations', async () => {
    const { service, fetchImpl } = setup();
    await service.orderUpdate('p1', 'ลูกค้ายกเลิกงาน', 'งาน FG1 ถูกยกเลิกแล้ว');
    expect(sentBody(fetchImpl).messages[0].template.text).toBe(
      'ลูกค้ายกเลิกงาน\nงาน FG1 ถูกยกเลิกแล้ว',
    );
    await service.orderUpdate(null, 'x', 'y');
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('does nothing when the flag is off', async () => {
    const { service, prisma, fetchImpl } = setup({ enabled: false });
    await service.offer(['p1'], ORDER, 90_000);
    await service.orderUpdate('p1', 'a', 'b');
    expect(prisma.provider.findMany).not.toHaveBeenCalled();
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('does nothing without a channel access token', async () => {
    const { service, fetchImpl } = setup({ token: undefined });
    await service.offer(['p1'], ORDER, 90_000);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('swallows LINE and database failures and still tries every mechanic', async () => {
    const { service, fetchImpl } = setup({}, [
      { id: 'p1', lineUserId: 'U1' },
      { id: 'p2', lineUserId: 'U2' },
      { id: 'p3', lineUserId: 'U3' },
    ]);
    fetchImpl
      .mockRejectedValueOnce(new Error('network down'))
      .mockResolvedValueOnce({ ok: false, status: 400 })
      .mockResolvedValueOnce({ ok: true, status: 200 });
    await expect(
      service.offer(['p1', 'p2', 'p3'], ORDER, 90_000),
    ).resolves.toBeUndefined();
    expect(fetchImpl).toHaveBeenCalledTimes(3);

    const broken = setup();
    broken.prisma.provider.findMany.mockRejectedValue(new Error('db down'));
    await expect(
      broken.service.offer(['p1'], ORDER, 90_000),
    ).resolves.toBeUndefined();
  });
});

describe('provider LINE config', () => {
  it('is off by default and reuses the admin OA token when no own token is set', () => {
    expect(readProviderLineConfig({}).enabled).toBe(false);
    const config = readProviderLineConfig({
      PROVIDER_LINE_ALERTS: 'true',
      LINE_CHANNEL_ACCESS_TOKEN: 'admin-oa',
      FIXER_DOMAIN: 'fixer.fixgo.example',
    });
    expect(config).toMatchObject({
      enabled: true,
      token: 'admin-oa',
      fixerUrl: 'https://fixer.fixgo.example',
    });
    expect(
      readProviderLineConfig({
        LINE_MESSAGING_TOKEN: 'own',
        LINE_CHANNEL_ACCESS_TOKEN: 'admin-oa',
      }).token,
    ).toBe('own');
  });

  it('shows the add-friend card only to LINE mechanics when alerts are on', () => {
    expect(providerLineAddFriendUrl({ lineUserId: 'U1' }, CONFIG)).toBe(
      'https://lin.ee/abc',
    );
    expect(providerLineAddFriendUrl({ lineUserId: null }, CONFIG)).toBeNull();
    expect(
      providerLineAddFriendUrl(
        { lineUserId: 'U1' },
        { ...CONFIG, enabled: false },
      ),
    ).toBeNull();
    expect(
      providerLineAddFriendUrl(
        { lineUserId: 'U1' },
        { ...CONFIG, addFriendUrl: undefined },
      ),
    ).toBeNull();
  });
});

describe('dispatchOfferTimeoutMs', () => {
  it('keeps 90 seconds unless configured', () => {
    expect(dispatchOfferTimeoutMs({})).toBe(90_000);
    expect(
      dispatchOfferTimeoutMs({ DISPATCH_OFFER_TIMEOUT_MS: '180000' }),
    ).toBe(180_000);
  });

  it('rejects values that would break dispatch', () => {
    for (const value of ['abc', '1000', '90.5', '3600000']) {
      expect(() =>
        dispatchOfferTimeoutMs({ DISPATCH_OFFER_TIMEOUT_MS: value }),
      ).toThrow('DISPATCH_OFFER_TIMEOUT_MS');
    }
  });
});
