/** คอมมิชชันที่แอปหักจากทุกงาน */
export const DEFAULT_COMMISSION_RATE = 0.35;

/** เวลาที่ช่างมีให้กดรับงาน ช่วงสั้นเพื่อให้ลูกค้าไม่รอนานในเหตุฉุกเฉิน */
export const DISPATCH_OFFER_TIMEOUT_MS = 90 * 1000;

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
