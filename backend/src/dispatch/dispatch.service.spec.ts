import {
  bangkokMinuteOfDay,
  DispatchService,
  isWithinWorkingHours,
} from './dispatch.service';
import { ProviderLineService } from '../notifications/provider-line.service';

describe('dispatch time helpers', () => {
  it('converts UTC to Bangkok time', () => {
    expect(bangkokMinuteOfDay(new Date('2026-09-20T00:30:00.000Z'))).toBe(
      7 * 60 + 30,
    );
  });

  it('handles a normal working window inclusively', () => {
    expect(isWithinWorkingHours(8 * 60, 18 * 60, 12 * 60)).toBe(true);
    expect(isWithinWorkingHours(8 * 60, 18 * 60, 7 * 60 + 59)).toBe(false);
  });

  it('handles a working window that crosses midnight', () => {
    expect(isWithinWorkingHours(20 * 60, 6 * 60, 23 * 60)).toBe(true);
    expect(isWithinWorkingHours(20 * 60, 6 * 60, 3 * 60)).toBe(true);
    expect(isWithinWorkingHours(20 * 60, 6 * 60, 12 * 60)).toBe(false);
  });

  it('treats the 24-hour preset (00:00-23:59) as always open', () => {
    for (const minute of [0, 6 * 60, 12 * 60, 23 * 60 + 59]) {
      expect(isWithinWorkingHours(0, 23 * 60 + 59, minute)).toBe(true);
    }
  });
});

describe('DispatchService LINE alerts', () => {
  const provider = {
    id: 'pro_1',
    openMinute: 0,
    closeMinute: 23 * 60 + 59,
    currentLat: 13.7,
    currentLng: 100.5,
    baseLat: 13.7,
    baseLng: 100.5,
  };

  function setup(fetchImpl: jest.Mock) {
    const prisma = {
      order: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        findUnique: jest.fn().mockResolvedValue({
          id: 'order_1',
          orderNo: 'FG1',
          status: 'SEARCHING',
          categoryId: 'cat',
          vehicleTypeId: 'car',
          pickupLat: 13.7,
          pickupLng: 100.5,
          pickupAddress: '99 ถนนบางนา-ตราด, บางนา, กรุงเทพมหานคร',
          priceEstimated: 50000,
          dispatchAttempts: [],
          subService: { name: 'จั๊มแบต' },
        }),
      },
      provider: {
        findMany: jest
          .fn()
          // รอบแรก: หาช่างที่จะเสนองาน รอบสอง: หา lineUserId ของช่าง
          .mockResolvedValueOnce([provider])
          .mockResolvedValueOnce([{ id: 'pro_1', lineUserId: 'U1' }]),
      },
      dispatchAttempt: { createMany: jest.fn().mockResolvedValue({}) },
    };
    const push = { offerToProviders: jest.fn().mockResolvedValue(undefined) };
    const line = new ProviderLineService(
      prisma as never,
      {
        enabled: true,
        token: 'line-token',
        fixerUrl: 'https://fixer.fixgo.example',
      },
      fetchImpl,
    );
    const dispatch = new DispatchService(
      prisma as never,
      push as never,
      {} as never,
      { emit: jest.fn() } as never,
      {} as never,
      line,
    );
    return { dispatch, prisma, push };
  }

  it('offers the job and sends LINE without waiting for it', async () => {
    // LINE ค้างไม่ตอบเลย: การเสนองานต้องไม่รอ
    const fetchImpl = jest.fn(() => new Promise(() => undefined));
    const { dispatch, prisma, push } = setup(fetchImpl as jest.Mock);
    await dispatch.startDispatch('order_1');
    expect(prisma.dispatchAttempt.createMany).toHaveBeenCalled();
    expect(push.offerToProviders).toHaveBeenCalled();
    await new Promise((resolve) => setImmediate(resolve));
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const init = (fetchImpl.mock.calls[0] as unknown[])[1] as { body: string };
    expect(JSON.parse(init.body).messages[0].template.text).toBe(
      '🔔 มีงานใหม่ใกล้คุณ\nจั๊มแบต · บางนา, กรุงเทพมหานคร\nราคาประเมิน ฿500\nกดรับภายใน 1 นาที',
    );
  });

  it('still offers the job when LINE fails', async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new Error('LINE down'));
    const { dispatch, prisma } = setup(fetchImpl);
    await expect(dispatch.startDispatch('order_1')).resolves.toBeUndefined();
    await new Promise((resolve) => setImmediate(resolve));
    expect(prisma.dispatchAttempt.createMany).toHaveBeenCalled();
    expect(fetchImpl).toHaveBeenCalled();
  });
});
