import { Role } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { PushSender } from './push-sender';
import { OrderEventsService } from './order-events.service';
import { PushService } from './push.service';

function setup(results: Record<string, 'sent' | 'invalid' | 'failed'>) {
  const devices = Object.keys(results).map((token) => ({ token }));
  const prisma = {
    deviceToken: {
      findMany: jest.fn().mockResolvedValue(devices),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      upsert: jest.fn(),
    },
  };
  const sender: PushSender & { send: jest.Mock } = {
    name: 'fake',
    send: jest.fn(async (token: string) => {
      if (results[token] === 'failed') throw new Error('network down');
      return results[token];
    }),
  };
  const events = new OrderEventsService();
  const service = new PushService(
    prisma as unknown as PrismaService,
    sender,
    events,
  );
  return { service, prisma, sender };
}

const order = { id: 'order_1', orderNo: 'FG2609240001' };

describe('PushService', () => {
  it('sends to every device of the customer with navigation data', async () => {
    const { service, prisma, sender } = setup({ t1: 'sent', t2: 'sent' });

    await service.completed('cus_1', order, 199000);

    expect(prisma.deviceToken.findMany).toHaveBeenCalledWith({
      where: { role: Role.CUSTOMER, userId: { in: ['cus_1'] } },
      select: { token: true },
    });
    expect(sender.send).toHaveBeenCalledTimes(2);
    expect(sender.send.mock.calls[0][1]).toEqual({
      title: 'งานเสร็จแล้ว',
      body: 'ยอดชำระ ฿1,990 ชำระและให้คะแนนช่างได้ในแอป',
      data: { type: 'COMPLETED', orderId: 'order_1', orderNo: 'FG2609240001' },
    });
  });

  it('removes invalid tokens and never throws on sender errors', async () => {
    const { service, prisma } = setup({
      good: 'sent',
      gone: 'invalid',
      flaky: 'failed',
    });

    await expect(
      service.offerToProviders(
        [{ id: 'pro_1', distanceKm: 2.14 }],
        { ...order, serviceName: 'จั๊มแบต' },
        90,
      ),
    ).resolves.toBeUndefined();

    expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({
      where: { token: { in: ['gone'] } },
    });
  });

  it('skips provider pushes when no provider is assigned', async () => {
    const { service, prisma } = setup({ t1: 'sent' });
    await service.cancelledByCustomer(null, order);
    expect(prisma.deviceToken.findMany).not.toHaveBeenCalled();
  });

  it('swallows database errors so business flows keep going', async () => {
    const { service, prisma } = setup({});
    prisma.deviceToken.findMany.mockRejectedValue(new Error('db down'));
    await expect(service.enRoute('cus_1', order)).resolves.toBeUndefined();
  });

  it('notifies only the customer for cash, both sides for PromptPay', async () => {
    const cash = setup({ t: 'sent' });
    await cash.service.paid('cus_1', 'pro_1', order, 50000, 'CASH');
    expect(cash.prisma.deviceToken.findMany).toHaveBeenCalledTimes(1);

    const qr = setup({ t: 'sent' });
    await qr.service.paid('cus_1', 'pro_1', order, 50000, 'PROMPTPAY');
    expect(qr.prisma.deviceToken.findMany).toHaveBeenCalledTimes(2);
  });
});

describe('PushService order events', () => {
  it('signals open tracking screens even when the user has no push token', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn(),
      },
    };
    const events = new OrderEventsService();
    const emit = jest.spyOn(events, 'emit');
    const service = new PushService(
      prisma as unknown as PrismaService,
      { name: 'fake', send: jest.fn() },
      events,
    );
    await service.enRoute('cus_1', { id: 'order_1', orderNo: 'FG1' });
    expect(emit).toHaveBeenCalledWith('order_1', 'EN_ROUTE');
  });
});

describe('PushService LINE for mechanics', () => {
  it('also sends quote answers and cancellations to the mechanic on LINE', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn(),
      },
    };
    const line = { orderUpdate: jest.fn().mockResolvedValue(undefined) };
    const service = new PushService(
      prisma as unknown as PrismaService,
      { name: 'fake', send: jest.fn() },
      new OrderEventsService(),
      line as never,
    );
    const order = { id: 'order_1', orderNo: 'FG1' };
    await service.quoteAnswered('pro_1', order, true);
    await service.cancelledByCustomer('pro_1', order);
    await service.paid('cus_1', 'pro_1', order, 50000, 'PROMPTPAY');
    expect(line.orderUpdate.mock.calls).toEqual([
      ['pro_1', 'ลูกค้ายืนยันราคาแล้ว', 'เริ่มงานได้เลย'],
      ['pro_1', 'ลูกค้ายกเลิกงาน', 'งาน FG1 ถูกยกเลิกแล้ว ไม่ต้องเดินทางต่อ'],
    ]);
  });
});

describe('PushService Web Push', () => {
  it('sends new jobs as urgent web pushes that expire with the offer', async () => {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([]),
        deleteMany: jest.fn(),
      },
    };
    const webPush = { send: jest.fn().mockResolvedValue(undefined) };
    const service = new PushService(
      prisma as unknown as PrismaService,
      { name: 'fake', send: jest.fn() },
      new OrderEventsService(),
      undefined,
      webPush as never,
    );
    const order = { id: 'order_1', orderNo: 'FG1' };
    await service.offerToProviders(
      [{ id: 'pro_1', distanceKm: 2.4 }],
      { ...order, serviceName: 'จั๊มแบต' },
      180,
    );
    await service.quoteAnswered('pro_1', order, true);
    expect(webPush.send.mock.calls).toEqual([
      [
        Role.PROVIDER,
        ['pro_1'],
        expect.objectContaining({ type: 'OFFER', orderId: 'order_1' }),
        { ttlSeconds: 180, urgent: true },
      ],
      [
        Role.PROVIDER,
        ['pro_1'],
        expect.objectContaining({ type: 'QUOTE_APPROVED' }),
        { ttlSeconds: undefined, urgent: false },
      ],
    ]);
  });
});

describe('PushService new-job alarm', () => {
  function build() {
    const prisma = {
      deviceToken: {
        findMany: jest.fn().mockResolvedValue([{ token: 't1' }]),
        deleteMany: jest.fn(),
      },
    };
    const sender = { name: 'fake', send: jest.fn().mockResolvedValue('sent') };
    const webPush = { send: jest.fn().mockResolvedValue(undefined) };
    const service = new PushService(
      prisma as unknown as PrismaService,
      sender,
      new OrderEventsService(),
      undefined,
      webPush as never,
    );
    return { service, sender, webPush };
  }

  it('rings until the offer expires', async () => {
    const { service, sender } = build();
    const before = Date.now();
    await service.offerToProviders(
      [{ id: 'pro_1', distanceKm: 1 }],
      { id: 'order_1', orderNo: 'FG1', serviceName: 'จั๊มแบต' },
      180,
    );
    const sent = sender.send.mock.calls[0][1];
    expect(sent.delivery.kind).toBe('alarm');
    expect(sent.delivery.collapseKey).toBe('order_1');
    const left = sent.delivery.expiresAt.getTime() - before;
    expect(left).toBeGreaterThanOrEqual(180_000);
    expect(left).toBeLessThan(185_000);
  });

  it('tells other mechanics to stop ringing, without a web push', async () => {
    const { service, sender, webPush } = build();
    await service.offerClosed(
      ['pro_2', 'pro_3', 'pro_2'],
      { id: 'order_1', orderNo: 'FG1' },
      'TAKEN',
    );
    const sent = sender.send.mock.calls[0][1];
    expect(sent.data.type).toBe('OFFER_CANCELLED');
    expect(sent.title).toBe('งานนี้มีช่างรับแล้ว');
    expect(sent.delivery).toEqual({ kind: 'close', collapseKey: 'order_1' });
    expect(webPush.send).not.toHaveBeenCalled();

    sender.send.mockClear();
    await service.offerClosed(
      ['pro_2'],
      { id: 'order_1', orderNo: 'FG1' },
      'EXPIRED',
    );
    expect(sender.send.mock.calls[0][1].data.type).toBe('OFFER_EXPIRED');

    sender.send.mockClear();
    await service.offerClosed([], { id: 'order_1', orderNo: 'FG1' }, 'EXPIRED');
    expect(sender.send).not.toHaveBeenCalled();
  });
});
