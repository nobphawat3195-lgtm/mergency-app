import * as webpush from 'web-push';

jest.mock('web-push', () => ({ sendNotification: jest.fn() }));

import {
  createWebPushSender,
  readWebPushConfig,
  WebPushConfig,
  WebPushService,
} from './web-push.service';

const CONFIG: WebPushConfig = {
  enabled: true,
  publicKey: 'BPublicKey',
  privateKey: 'private',
  subject: 'mailto:ops@fixgo.example',
};

const ORDER_ID = '0b5f45aa-16a3-4b7b-8c7e-ecf8f1122821';

function setup(
  statuses: Record<string, number | Error>,
  config: WebPushConfig = CONFIG,
) {
  const rows = Object.keys(statuses).map((endpoint) => ({
    endpoint,
    p256dh: `p-${endpoint}`,
    auth: `a-${endpoint}`,
  }));
  const prisma = {
    webPushSubscription: {
      findMany: jest.fn().mockResolvedValue(rows),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      upsert: jest.fn().mockResolvedValue({}),
    },
  };
  const sender = jest.fn(async (target: { endpoint: string }) => {
    const result = statuses[target.endpoint];
    if (result instanceof Error) throw result;
    return result;
  });
  const service = new WebPushService(prisma as never, config, sender);
  return { service, prisma, sender };
}

const message = {
  title: 'มีงานใหม่ใกล้คุณ',
  body: 'จั๊มแบต · ห่าง 2.4 กม.',
  type: 'OFFER',
  orderId: ORDER_ID,
  orderNo: 'FG1',
};

describe('WebPushService', () => {
  it('sends a new job as an urgent push that expires with the offer', async () => {
    const { service, prisma, sender } = setup({ 'https://push/a': 201 });
    await service.send('PROVIDER', ['pro_1'], message, {
      ttlSeconds: 180,
      urgent: true,
    });
    expect(prisma.webPushSubscription.findMany).toHaveBeenCalledWith({
      where: { role: 'PROVIDER', userId: { in: ['pro_1'] } },
      select: { endpoint: true, p256dh: true, auth: true },
    });
    expect(sender).toHaveBeenCalledWith(
      {
        endpoint: 'https://push/a',
        keys: { p256dh: 'p-https://push/a', auth: 'a-https://push/a' },
      },
      JSON.stringify(message),
      {
        TTL: 180,
        urgency: 'high',
        topic: ORDER_ID.replace(/-/g, ''),
      },
    );
    const topic = (sender.mock.calls[0] as unknown[])[2] as { topic: string };
    expect(topic.topic).toHaveLength(32);
    expect(prisma.webPushSubscription.deleteMany).not.toHaveBeenCalled();
  });

  it('prunes subscriptions the push service says are gone and keeps going', async () => {
    const { service, prisma, sender } = setup({
      'https://push/gone': 410,
      'https://push/missing': 404,
      'https://push/limit': 429,
      'https://push/down': new Error('network down'),
      'https://push/ok': 201,
    });
    await expect(
      service.send('PROVIDER', ['pro_1'], message),
    ).resolves.toBeUndefined();
    expect(sender).toHaveBeenCalledTimes(5);
    expect(prisma.webPushSubscription.deleteMany).toHaveBeenCalledWith({
      where: {
        endpoint: { in: ['https://push/gone', 'https://push/missing'] },
      },
    });
  });

  it('never throws when the database fails', async () => {
    const { service, prisma } = setup({});
    prisma.webPushSubscription.findMany.mockRejectedValue(new Error('db'));
    await expect(
      service.send('PROVIDER', ['pro_1'], message),
    ).resolves.toBeUndefined();
  });

  it('does nothing when Web Push is off', async () => {
    const { service, prisma, sender } = setup(
      { 'https://push/a': 201 },
      { ...CONFIG, enabled: false },
    );
    await service.send('PROVIDER', ['pro_1'], message);
    expect(prisma.webPushSubscription.findMany).not.toHaveBeenCalled();
    expect(sender).not.toHaveBeenCalled();
    expect(service.publicConfig()).toEqual({
      enabled: false,
      publicKey: null,
    });
  });

  it('moves a browser to the account that signed in last', async () => {
    const { service, prisma } = setup({});
    await service.subscribe('pro_2', 'PROVIDER', {
      endpoint: 'https://push/a',
      keys: { p256dh: 'p', auth: 'a' },
    });
    expect(prisma.webPushSubscription.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { endpoint: 'https://push/a' },
        update: expect.objectContaining({ userId: 'pro_2', p256dh: 'p' }),
      }),
    );
  });
});

describe('Web Push config', () => {
  it('needs the flag and all three VAPID values', () => {
    const env = {
      WEB_PUSH_ENABLED: 'true',
      VAPID_PUBLIC_KEY: 'pub',
      VAPID_PRIVATE_KEY: 'priv',
      VAPID_SUBJECT: 'mailto:ops@fixgo.example',
    };
    expect(readWebPushConfig(env).enabled).toBe(true);
    expect(readWebPushConfig({ ...env, WEB_PUSH_ENABLED: '' }).enabled).toBe(
      false,
    );
    expect(readWebPushConfig({ ...env, VAPID_PRIVATE_KEY: '' }).enabled).toBe(
      false,
    );
    expect(readWebPushConfig({}).enabled).toBe(false);
  });

  it('reports the push service status instead of throwing', async () => {
    const spy = (webpush.sendNotification as jest.Mock)
      .mockRejectedValueOnce(
        Object.assign(new Error('Received unexpected response code'), {
          statusCode: 410,
        }),
      )
      .mockResolvedValueOnce({ statusCode: 201, body: '', headers: {} });
    const send = createWebPushSender(CONFIG);
    const target = {
      endpoint: 'https://push/a',
      keys: { p256dh: 'p', auth: 'a' },
    };
    const options = { TTL: 60, urgency: 'high' as const };
    await expect(send(target, '{}', options)).resolves.toBe(410);
    await expect(send(target, '{}', options)).resolves.toBe(201);
    expect(spy.mock.calls[1][2]).toMatchObject({
      TTL: 60,
      urgency: 'high',
      vapidDetails: {
        subject: CONFIG.subject,
        publicKey: CONFIG.publicKey,
        privateKey: CONFIG.privateKey,
      },
    });
  });
});
