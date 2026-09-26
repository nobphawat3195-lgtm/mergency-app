import { AdminAlertService, coarseArea } from './admin-alert.service';

type Call = [string, { headers: Record<string, string>; body: string }];

describe('AdminAlertService', () => {
  const order = {
    orderNo: 'FG2609250001',
    serviceName: 'จั๊มแบต',
    area: 'บางกะปิ, กรุงเทพฯ',
  };

  it('pushes to a LINE group through the Messaging API', async () => {
    const fetch = jest.fn().mockResolvedValue({ ok: true, status: 200 });
    const service = new AdminAlertService(
      {
        channel: 'line',
        lineToken: 'line-token',
        lineTo: 'C123',
        adminUrl: 'https://admin.fixgo.test',
      },
      fetch,
    );

    await service.noMatch(order);

    const [url, init] = fetch.mock.calls[0] as Call;
    expect(url).toBe('https://api.line.me/v2/bot/message/push');
    expect(init.headers.Authorization).toBe('Bearer line-token');
    const body = JSON.parse(init.body);
    expect(body.to).toBe('C123');
    expect(body.messages[0].text).toContain('FG2609250001');
    expect(body.messages[0].text).toContain('https://admin.fixgo.test');
  });

  it('posts Slack and Discord compatible JSON to a webhook', async () => {
    const fetch = jest.fn().mockResolvedValue({ ok: true, status: 204 });
    const service = new AdminAlertService(
      { channel: 'webhook', webhookUrl: 'https://hooks.example/abc' },
      fetch,
    );
    await service.withdrawalRequested('ต้น', '฿1,200');
    const body = JSON.parse((fetch.mock.calls[0] as Call)[1].body);
    expect(body.text).toContain('฿1,200');
    expect(body.content).toBe(body.text);
  });

  it('never throws when the channel is down or misconfigured', async () => {
    const failing = new AdminAlertService(
      { channel: 'line', lineToken: 't', lineTo: 'C1' },
      jest.fn().mockRejectedValue(new Error('network')),
    );
    await expect(failing.providerApplied('ต้น')).resolves.toBeUndefined();

    const incomplete = new AdminAlertService({ channel: 'line' }, jest.fn());
    await expect(incomplete.noMatch(order)).resolves.toBeUndefined();
  });

  it('keeps only the district and province of an address', () => {
    expect(coarseArea('99/1 ซอยทดสอบ, แขวงคลองจั่น, บางกะปิ, กรุงเทพฯ')).toBe(
      'บางกะปิ, กรุงเทพฯ',
    );
    expect(coarseArea(null)).toBeNull();
  });
});
