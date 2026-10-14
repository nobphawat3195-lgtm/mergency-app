import { createVerify, generateKeyPairSync } from 'node:crypto';

import {
  buildFcmMessage,
  createPushSender,
  FcmPushSender,
  PushMessage,
} from './push-sender';

const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
});

const credentials = {
  projectId: 'fixgo-test',
  clientEmail: 'push@fixgo-test.iam.gserviceaccount.com',
  privateKey,
};

const message: PushMessage = {
  title: 'มีงานใหม่ใกล้คุณ',
  body: 'จั๊มแบต · ห่าง 2.1 กม.',
  data: { type: 'OFFER', orderId: 'order_1', orderNo: 'FG1' },
};

function response(status: number, body: unknown) {
  return { ok: status < 300, status, json: async () => body };
}

function fakeFetch(sendStatus = 200, sendBody: unknown = { name: 'x' }) {
  return jest.fn(async (url: string) =>
    url.startsWith('https://oauth2.googleapis.com')
      ? response(200, { access_token: 'ya29.token', expires_in: 3600 })
      : response(sendStatus, sendBody),
  );
}

describe('FcmPushSender', () => {
  it('signs a service-account JWT and sends an HTTP v1 message', async () => {
    const fetch = fakeFetch();
    const sender = new FcmPushSender(credentials, fetch);

    await expect(sender.send('device-token-1', message)).resolves.toBe('sent');

    const [oauthUrl, oauthInit] = fetch.mock.calls[0] as unknown as [
      string,
      { body: string },
    ];
    expect(oauthUrl).toBe('https://oauth2.googleapis.com/token');
    const assertion = new URLSearchParams(oauthInit.body).get('assertion')!;
    const [header, claims, signature] = assertion.split('.');
    const verifier = createVerify('RSA-SHA256');
    verifier.update(`${header}.${claims}`);
    expect(verifier.verify(publicKey, signature, 'base64url')).toBe(true);
    expect(
      JSON.parse(Buffer.from(claims, 'base64url').toString()),
    ).toMatchObject({
      iss: credentials.clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
    });

    const [sendUrl, sendInit] = fetch.mock.calls[1] as unknown as [
      string,
      { headers: Record<string, string>; body: string },
    ];
    expect(sendUrl).toBe(
      'https://fcm.googleapis.com/v1/projects/fixgo-test/messages:send',
    );
    expect(sendInit.headers.Authorization).toBe('Bearer ya29.token');
    const payload = JSON.parse(sendInit.body).message;
    expect(payload.token).toBe('device-token-1');
    expect(payload.notification).toEqual({
      title: message.title,
      body: message.body,
    });
    expect(payload.data).toEqual(message.data);
    expect(payload.android.priority).toBe('HIGH');
  });

  it('reuses the access token until it is about to expire', async () => {
    const fetch = fakeFetch();
    let now = 1_000_000;
    const sender = new FcmPushSender(credentials, fetch, () => now);

    await sender.send('a'.repeat(30), message);
    await sender.send('b'.repeat(30), message);
    const oauthCalls = () =>
      fetch.mock.calls.filter(([url]) => url.includes('oauth2')).length;
    expect(oauthCalls()).toBe(1);

    now += 3600 * 1000;
    await sender.send('c'.repeat(30), message);
    expect(oauthCalls()).toBe(2);
  });

  it('reports unregistered tokens as invalid so they get removed', async () => {
    const sender = new FcmPushSender(
      credentials,
      fakeFetch(404, {
        error: {
          status: 'NOT_FOUND',
          details: [{ errorCode: 'UNREGISTERED' }],
        },
      }),
    );
    await expect(sender.send('gone', message)).resolves.toBe('invalid');
  });

  it('keeps the token on transient server errors', async () => {
    const sender = new FcmPushSender(
      credentials,
      fakeFetch(503, { error: { status: 'UNAVAILABLE' } }),
    );
    await expect(sender.send('ok', message)).resolves.toBe('failed');
  });
});

describe('createPushSender', () => {
  it('falls back to console when no provider is configured', () => {
    expect(createPushSender({}).name).toBe('console');
  });

  it('refuses fcm without credentials instead of silently dropping pushes', () => {
    expect(() => createPushSender({ PUSH_PROVIDER: 'fcm' })).toThrow(
      /FCM_PROJECT_ID/,
    );
  });

  it('accepts a private key with escaped newlines from env files', () => {
    const sender = createPushSender({
      PUSH_PROVIDER: 'fcm',
      FCM_PROJECT_ID: 'p',
      FCM_CLIENT_EMAIL: 'e@p.iam.gserviceaccount.com',
      FCM_PRIVATE_KEY: privateKey.replace(/\n/g, '\\n'),
    });
    expect(sender.name).toBe('fcm');
  });
});

describe('buildFcmMessage', () => {
  const NOW = Date.parse('2026-10-14T10:00:00Z');
  const expiresAt = new Date(NOW + 180_000);

  it('sends a new job as a data-only high-priority alarm on Android and time-sensitive on iOS', () => {
    const built = buildFcmMessage(
      'tok',
      {
        ...message,
        delivery: { kind: 'alarm', expiresAt, collapseKey: 'order_1' },
      },
      NOW,
    );
    // ไม่มี notification: แอปช่างแสดงแจ้งเตือนแบบนาฬิกาปลุกเองแม้ถูกปิดอยู่
    expect(built.notification).toBeUndefined();
    expect(built.data).toEqual({
      type: 'OFFER',
      orderId: 'order_1',
      orderNo: 'FG1',
      title: message.title,
      body: message.body,
      expiresAt: expiresAt.toISOString(),
      channelId: 'fixgo_offer_alarm',
    });
    expect(built.android).toEqual({
      priority: 'HIGH',
      ttl: '180s',
      collapse_key: 'order_1',
    });
    expect(built.apns).toEqual({
      headers: {
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-expiration': String(Math.floor(expiresAt.getTime() / 1000)),
        'apns-collapse-id': 'order_1',
      },
      payload: {
        aps: {
          alert: { title: message.title, body: message.body },
          sound: 'offer_alarm.caf',
          'interruption-level': 'time-sensitive',
          'thread-id': 'order_1',
        },
      },
    });
    // ค่า data ของ FCM ต้องเป็น string ทุกตัว
    for (const value of Object.values(built.data as object)) {
      expect(typeof value).toBe('string');
    }
  });

  it('never asks FCM to keep an offer that already expired', () => {
    const built = buildFcmMessage(
      'tok',
      {
        ...message,
        delivery: {
          kind: 'alarm',
          expiresAt: new Date(NOW - 5000),
          collapseKey: 'order_1',
        },
      },
      NOW,
    );
    expect((built.android as { ttl: string }).ttl).toBe('1s');
  });

  it('closes the alarm quietly: data-only on Android, a passive replacement on iOS', () => {
    const built = buildFcmMessage('tok', {
      title: 'งานนี้มีช่างรับแล้ว',
      body: 'งาน FG1 ไม่ต้องตอบรับแล้ว',
      data: { type: 'OFFER_CANCELLED', orderId: 'order_1', orderNo: 'FG1' },
      delivery: { kind: 'close', collapseKey: 'order_1' },
    });
    expect(built.notification).toBeUndefined();
    const apns = built.apns as {
      headers: Record<string, string>;
      payload: { aps: Record<string, unknown> };
    };
    expect(apns.headers['apns-collapse-id']).toBe('order_1');
    expect(apns.payload.aps['interruption-level']).toBe('passive');
    expect(apns.payload.aps.sound).toBeUndefined();
  });

  it('keeps ordinary updates on the normal channel', () => {
    const built = buildFcmMessage('tok', message);
    expect(built.notification).toEqual({
      title: message.title,
      body: message.body,
    });
    expect(
      (built.android as { notification: { channel_id: string } }).notification
        .channel_id,
    ).toBe('fixgo_updates');
  });
});
