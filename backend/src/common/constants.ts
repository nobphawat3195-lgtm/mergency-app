/** ค่าบริการแพลตฟอร์มเริ่มต้น ใช้เมื่อไม่ได้ตั้ง COMMISSION_RATE */
export const DEFAULT_COMMISSION_RATE = 0.35;

/**
 * ค่าบริการแพลตฟอร์มที่หักจากงานใหม่ (0–1) ตั้งได้ด้วย env COMMISSION_RATE
 * อัตราจริงจึงไม่ต้องอยู่ในโค้ดหรือเอกสารสาธารณะ งานเดิมเก็บอัตราของตัวเองไว้ใน order.commissionRate
 */
export function commissionRate(env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.COMMISSION_RATE?.trim();
  if (!raw) return DEFAULT_COMMISSION_RATE;
  const rate = Number(raw);
  if (!Number.isFinite(rate) || rate <= 0 || rate >= 1) {
    throw new Error(
      'COMMISSION_RATE must be a number between 0 and 1, e.g. 0.3',
    );
  }
  return rate;
}

/** เพดานค่าบริการค้างเริ่มต้น (บาท) ใช้เมื่อไม่ได้ตั้ง CASH_DEBT_LIMIT_BAHT */
export const DEFAULT_CASH_DEBT_LIMIT_BAHT = 1000;

/**
 * งานเงินสดทำให้ช่างค้างค่าบริการแพลตฟอร์ม (ยอดกระเป๋าติดลบ)
 * ถ้าค้างเกินเพดานนี้ ช่างเปิดรับงานไม่ได้จนกว่าจะโอนคืน คืนค่าเป็นสตางค์
 */
export function cashDebtLimit(env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.CASH_DEBT_LIMIT_BAHT?.trim();
  if (!raw) return DEFAULT_CASH_DEBT_LIMIT_BAHT * 100;
  const baht = Number(raw);
  if (!Number.isFinite(baht) || baht < 0) {
    throw new Error('CASH_DEBT_LIMIT_BAHT must be a number of baht >= 0');
  }
  return Math.round(baht * 100);
}

/** เวลาที่ช่างมีให้กดรับงาน ช่วงสั้นเพื่อให้ลูกค้าไม่รอนานในเหตุฉุกเฉิน */
export const DEFAULT_DISPATCH_OFFER_TIMEOUT_MS = 90 * 1000;

/**
 * ปรับได้ด้วย env DISPATCH_OFFER_TIMEOUT_MS (มิลลิวินาที 15 วินาที - 15 นาที)
 * เช่น 180000 ให้ช่างที่ได้แจ้งเตือนทาง LINE มีเวลาเปิดเว็บแอปมากดรับ
 */
export function dispatchOfferTimeoutMs(
  env: NodeJS.ProcessEnv = process.env,
): number {
  const raw = env.DISPATCH_OFFER_TIMEOUT_MS?.trim();
  if (!raw) return DEFAULT_DISPATCH_OFFER_TIMEOUT_MS;
  const ms = Number(raw);
  if (!Number.isInteger(ms) || ms < 15_000 || ms > 15 * 60_000) {
    throw new Error(
      'DISPATCH_OFFER_TIMEOUT_MS must be milliseconds between 15000 and 900000',
    );
  }
  return ms;
}

/** ส่งพร้อมกันเป็นกลุ่ม คนแรกที่กดรับได้งาน */
export const DISPATCH_BATCH_SIZE = 4;

/** รัศมีสูงสุดที่จะส่งงานให้ช่าง */
export const DISPATCH_MAX_RADIUS_KM = 25;

/** จำนวนช่างสูงสุดที่จะไล่เสนองานต่อ 1 ออเดอร์ */
export const DISPATCH_MAX_CANDIDATES = 12;

/** ไม่ส่งงานให้ช่างที่ไม่มี heartbeat ภายในช่วงนี้ แม้สถานะ isOnline ยังค้างอยู่ */
export const PROVIDER_HEARTBEAT_STALE_MS = 2 * 60 * 1000;

export const OTP_TTL_MS = 5 * 60 * 1000;
export const OTP_MAX_ATTEMPTS = 5;
