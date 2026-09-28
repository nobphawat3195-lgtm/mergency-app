import { OrderStatus, ProviderStatus } from '@prisma/client';

import {
  LOCATION_FRESH_MS,
  liveProviderPosition,
  presentProviderCard,
} from './provider-card';

const NOW = Date.parse('2026-09-28T10:00:00Z');

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
  // ห่างจุดนัดราว 5.6 กม.
  currentLat: 13.8,
  currentLng: 100.55,
  locationAt: new Date(NOW - 60_000),
  _count: { orders: 31 },
};

const order = (status: OrderStatus) => ({
  status,
  pickupLat: 13.75,
  pickupLng: 100.55,
});

describe('liveProviderPosition', () => {
  it('shows the mechanic while they are on the way', () => {
    for (const status of [OrderStatus.MATCHED, OrderStatus.EN_ROUTE]) {
      const live = liveProviderPosition(order(status), provider, NOW);
      expect(live).toMatchObject({ lat: 13.8, lng: 100.55 });
      expect(live!.distanceKm).toBeCloseTo(5.6, 1);
      expect(live!.etaMinutes).toBeGreaterThan(10);
    }
  });

  it('hides the mechanic once they arrive or the job ends', () => {
    for (const status of [
      OrderStatus.IN_PROGRESS,
      OrderStatus.COMPLETED,
      OrderStatus.CANCELLED,
      OrderStatus.SEARCHING,
    ]) {
      expect(liveProviderPosition(order(status), provider, NOW)).toBeNull();
    }
  });

  it('does not present a stale position as live', () => {
    const stale = {
      ...provider,
      locationAt: new Date(NOW - LOCATION_FRESH_MS - 1),
    };
    expect(
      liveProviderPosition(order(OrderStatus.EN_ROUTE), stale, NOW),
    ).toBeNull();
  });

  it('needs a reported position', () => {
    const unknown = { ...provider, currentLat: null, currentLng: null };
    expect(
      liveProviderPosition(order(OrderStatus.EN_ROUTE), unknown, NOW),
    ).toBeNull();
  });
});

describe('presentProviderCard', () => {
  it('builds the trust card without internal fields', () => {
    const card = presentProviderCard(
      order(OrderStatus.EN_ROUTE),
      provider,
      NOW,
    );
    expect(card).toMatchObject({
      nickname: 'ชาย',
      verified: true,
      completedJobs: 31,
      ratingCount: 25,
      vehiclePlate: 'กข 1234',
    });
    expect(card.etaMinutes).not.toBeNull();
    expect(card).not.toHaveProperty('status');
    expect(card).not.toHaveProperty('locationAt');
    expect(card).not.toHaveProperty('_count');
  });

  it('masks the location after the mechanic arrives', () => {
    const card = presentProviderCard(
      order(OrderStatus.IN_PROGRESS),
      provider,
      NOW,
    );
    expect(card.currentLat).toBeNull();
    expect(card.currentLng).toBeNull();
    expect(card.etaMinutes).toBeNull();
  });
});
