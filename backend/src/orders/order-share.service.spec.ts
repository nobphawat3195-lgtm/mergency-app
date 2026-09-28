import { NotFoundException, BadRequestException } from '@nestjs/common';
import { OrderStatus, ProviderStatus } from '@prisma/client';

import {
  OrderShareService,
  SHARE_GRACE_MS,
  SHARE_TOKEN,
} from './order-share.service';

const NOW = Date.parse('2026-09-28T10:00:00Z');
const TOKEN = 'a'.repeat(43);

function makePrisma(order: Record<string, unknown> | null) {
  return {
    order: {
      findUnique: jest.fn().mockResolvedValue(order),
      update: jest.fn().mockResolvedValue({}),
      updateMany: jest.fn().mockResolvedValue({ count: order ? 1 : 0 }),
    },
  };
}

const provider = {
  id: 'prov_1',
  realName: 'สมชาย ใจดี',
  nickname: 'ชาย',
  phone: '0811111111',
  ratingAvg: 4.8,
  ratingCount: 25,
  experienceYears: 8,
  photoUrl: null,
  vehicleDesc: 'กระบะสีขาว',
  vehiclePlate: 'กข 1234',
  status: ProviderStatus.VERIFIED,
  createdAt: new Date('2026-01-01T00:00:00Z'),
  currentLat: 13.8,
  currentLng: 100.55,
  locationAt: new Date(NOW - 30_000),
  _count: { orders: 31 },
};

const sharedOrder = (overrides: Record<string, unknown> = {}) => ({
  status: OrderStatus.EN_ROUTE,
  pickupLat: 13.75,
  pickupLng: 100.55,
  createdAt: new Date(NOW - 20 * 60_000),
  matchedAt: new Date(NOW - 15 * 60_000),
  completedAt: null,
  cancelledAt: null,
  category: { name: 'ช่างแบตเตอรี่รถยนต์' },
  subService: { name: 'จั๊มแบต (นอกสถานที่)' },
  provider,
  ...overrides,
});

describe('OrderShareService.share', () => {
  const saved = process.env.PUBLIC_WEB_URL;
  afterEach(() => {
    if (saved === undefined) delete process.env.PUBLIC_WEB_URL;
    else process.env.PUBLIC_WEB_URL = saved;
  });

  it('creates an unguessable token once and reuses it', async () => {
    process.env.PUBLIC_WEB_URL = 'https://fixgo.example/';
    const prisma = makePrisma({
      customerId: 'cus_1',
      status: OrderStatus.SEARCHING,
      shareToken: null,
    });
    const service = new OrderShareService(prisma as never);
    const first = await service.share('ord_1', 'cus_1');
    expect(first.token).toMatch(SHARE_TOKEN);
    expect(first.url).toBe(`https://fixgo.example/track/${first.token}`);
    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'ord_1' },
      data: { shareToken: first.token },
    });

    prisma.order.findUnique.mockResolvedValue({
      customerId: 'cus_1',
      status: OrderStatus.EN_ROUTE,
      shareToken: first.token,
    });
    const again = await service.share('ord_1', 'cus_1');
    expect(again.token).toBe(first.token);
    expect(prisma.order.update).toHaveBeenCalledTimes(1);
  });

  it('hides other customers orders', async () => {
    const prisma = makePrisma({
      customerId: 'cus_other',
      status: OrderStatus.SEARCHING,
      shareToken: null,
    });
    const service = new OrderShareService(prisma as never);
    await expect(service.share('ord_1', 'cus_1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('does not share a finished job', async () => {
    const prisma = makePrisma({
      customerId: 'cus_1',
      status: OrderStatus.COMPLETED,
      shareToken: null,
    });
    const service = new OrderShareService(prisma as never);
    await expect(service.share('ord_1', 'cus_1')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});

describe('OrderShareService.view', () => {
  it('shows status and the mechanic on the way without contact details', async () => {
    const service = new OrderShareService(makePrisma(sharedOrder()) as never);
    const view = await service.view(TOKEN, NOW);
    expect(view.status).toBe(OrderStatus.EN_ROUTE);
    expect(view.provider).toMatchObject({
      nickname: 'ชาย',
      vehiclePlate: 'กข 1234',
      currentLat: 13.8,
    });
    expect(view.provider?.etaMinutes).toBeGreaterThan(0);
    const json = JSON.stringify(view);
    expect(json).not.toContain('0811111111');
    expect(json).not.toContain('สมชาย');
    expect(view).not.toHaveProperty('priceEstimated');
  });

  it('rejects malformed tokens without touching the database', async () => {
    const prisma = makePrisma(sharedOrder());
    const service = new OrderShareService(prisma as never);
    await expect(service.view('short', NOW)).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(prisma.order.findUnique).not.toHaveBeenCalled();
  });

  it('keeps working shortly after the job ends, then expires', async () => {
    const recent = sharedOrder({
      status: OrderStatus.COMPLETED,
      completedAt: new Date(NOW - 10 * 60_000),
    });
    const service = new OrderShareService(makePrisma(recent) as never);
    const view = await service.view(TOKEN, NOW);
    expect(view.provider?.currentLat).toBeNull();

    const old = sharedOrder({
      status: OrderStatus.CANCELLED,
      cancelledAt: new Date(NOW - SHARE_GRACE_MS - 1),
    });
    const expired = new OrderShareService(makePrisma(old) as never);
    await expect(expired.view(TOKEN, NOW)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
