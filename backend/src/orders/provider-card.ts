import { OrderStatus, ProviderStatus } from '@prisma/client';

import { distanceKm, estimateEtaMinutes } from '../common/geo';

/** ข้อมูลช่างที่ดึงมาพร้อมงาน ใช้สร้างการ์ดช่างที่ลูกค้าเห็น */
export const PROVIDER_CARD_SELECT = {
  id: true,
  realName: true,
  nickname: true,
  phone: true,
  ratingAvg: true,
  ratingCount: true,
  experienceYears: true,
  photoUrl: true,
  vehicleDesc: true,
  vehiclePlate: true,
  status: true,
  createdAt: true,
  currentLat: true,
  currentLng: true,
  locationAt: true,
  _count: { select: { orders: { where: { status: OrderStatus.COMPLETED } } } },
} as const;

/** แสดงตำแหน่งช่างเฉพาะช่วงที่ช่างกำลังมาหาลูกค้า ถึงหน้างานแล้วหรือจบงานแล้วไม่ต้องเห็น */
const LIVE_LOCATION_STATUSES: OrderStatus[] = [
  OrderStatus.MATCHED,
  OrderStatus.EN_ROUTE,
];

/** ตำแหน่งที่ไม่อัปเดตนานกว่านี้ถือว่าเก่า ไม่แสดงเป็นตำแหน่งสด */
export const LOCATION_FRESH_MS = 10 * 60_000;

interface ProviderRow {
  id: string;
  realName: string;
  nickname: string;
  phone: string;
  ratingAvg: number;
  ratingCount: number;
  experienceYears: number;
  photoUrl: string | null;
  vehicleDesc: string | null;
  vehiclePlate: string | null;
  status: ProviderStatus;
  createdAt: Date;
  currentLat: number | null;
  currentLng: number | null;
  locationAt: Date | null;
  _count: { orders: number };
}

interface OrderPosition {
  status: OrderStatus;
  pickupLat: number;
  pickupLng: number;
}

export interface LivePosition {
  lat: number;
  lng: number;
  updatedAt: Date;
  distanceKm: number;
  etaMinutes: number;
}

export function liveProviderPosition(
  order: OrderPosition,
  provider: Pick<ProviderRow, 'currentLat' | 'currentLng' | 'locationAt'>,
  now: number = Date.now(),
): LivePosition | null {
  if (!LIVE_LOCATION_STATUSES.includes(order.status)) return null;
  const { currentLat, currentLng, locationAt } = provider;
  if (currentLat == null || currentLng == null || locationAt == null) {
    return null;
  }
  if (now - locationAt.getTime() > LOCATION_FRESH_MS) return null;
  const km = distanceKm(
    currentLat,
    currentLng,
    order.pickupLat,
    order.pickupLng,
  );
  return {
    lat: currentLat,
    lng: currentLng,
    updatedAt: locationAt,
    distanceKm: Math.round(km * 10) / 10,
    etaMinutes: estimateEtaMinutes(km),
  };
}

/**
 * การ์ดช่างสำหรับลูกค้า: ข้อมูลที่ช่วยให้มั่นใจว่าเป็นช่างตัวจริง
 * ตำแหน่งช่างส่งเฉพาะตอนกำลังเดินทางมาและยังสด (ความเป็นส่วนตัวของช่าง)
 */
export function presentProviderCard(
  order: OrderPosition,
  provider: ProviderRow,
  now: number = Date.now(),
) {
  const live = liveProviderPosition(order, provider, now);
  return {
    id: provider.id,
    realName: provider.realName,
    nickname: provider.nickname,
    phone: provider.phone,
    ratingAvg: provider.ratingAvg,
    ratingCount: provider.ratingCount,
    experienceYears: provider.experienceYears,
    photoUrl: provider.photoUrl,
    vehicleDesc: provider.vehicleDesc,
    vehiclePlate: provider.vehiclePlate,
    verified: provider.status === ProviderStatus.VERIFIED,
    completedJobs: provider._count.orders,
    memberSince: provider.createdAt,
    currentLat: live?.lat ?? null,
    currentLng: live?.lng ?? null,
    locationUpdatedAt: live?.updatedAt ?? null,
    distanceKm: live?.distanceKm ?? null,
    etaMinutes: live?.etaMinutes ?? null,
  };
}
