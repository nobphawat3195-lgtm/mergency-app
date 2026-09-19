/** คอมมิชชันที่แอปหักจากทุกงาน */
export const DEFAULT_COMMISSION_RATE = 0.35;

/** เวลาที่ช่างมีให้กดรับงานก่อนส่งต่อคนถัดไป */
export const DISPATCH_OFFER_TIMEOUT_MS = 5 * 60 * 1000;

/** รัศมีสูงสุดที่จะส่งงานให้ช่าง */
export const DISPATCH_MAX_RADIUS_KM = 25;

/** จำนวนช่างสูงสุดที่จะไล่เสนองานต่อ 1 ออเดอร์ */
export const DISPATCH_MAX_CANDIDATES = 10;

export const OTP_TTL_MS = 5 * 60 * 1000;
export const OTP_MAX_ATTEMPTS = 5;
