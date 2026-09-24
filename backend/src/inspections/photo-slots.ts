/**
 * ช่องภาพหลักฐานของงานตรวจรถมือสอง แยกเป็นหัวข้อตามมุมสำคัญที่ต้องถ่าย
 *
 * ช่างถ่ายด้วยกล้องของเครื่องระหว่างเดินตรวจ แล้วเลือกจากคลังรูปมาแนบทีละช่อง
 * ช่อง required ต้องมีรูปอย่างน้อย 1 รูปก่อนส่งรายงาน ช่อง "ตำหนิ" ต้องมีคำอธิบายทุกรูป
 * เป็นแหล่งข้อมูลเดียว: แอปช่างใช้สร้างฟอร์ม แอปลูกค้าใช้จัดกลุ่มรูปในรายงาน
 */
export interface PhotoSlot {
  code: string;
  group: string;
  label: string;
  hint?: string;
  required: boolean;
  maxPhotos: number;
  /** ทุกรูปในช่องนี้ต้องมีคำอธิบาย เช่น ตำแหน่งตำหนิ */
  captionRequired?: boolean;
}

const slot = (
  code: string,
  group: string,
  label: string,
  options: Partial<Omit<PhotoSlot, 'code' | 'group' | 'label'>> = {},
): PhotoSlot => ({
  code,
  group,
  label,
  required: true,
  maxPhotos: 2,
  ...options,
});

const AROUND = 'รอบคัน';
const STRUCTURE = 'เสา A/B/C และโครงสร้าง';
const ENGINE_DOCS = 'ห้องเครื่องและเลขตัวรถ';
const CABIN_GROUP = 'ภายในห้องโดยสาร';
const DEFECT = 'ตำหนิที่พบ';

// เก็บเฉพาะมุมสำคัญ ช่างถ่ายครบได้ในไม่กี่นาที แต่ละช่องมีภาพตัวอย่างมุมถ่ายในแอป
// (packages/fixgo_core/assets/guides/<code>.png) ให้ช่างเลือกรูปให้ตรงหัวข้อ
export const PHOTO_SLOTS: PhotoSlot[] = [
  slot('EXT_FRONT', AROUND, 'ด้านหน้ารถ', {
    hint: 'ยืนตรงหน้ารถ ให้เห็นกันชนและไฟหน้าทั้งสองข้าง',
  }),
  slot('EXT_REAR', AROUND, 'ด้านหลังรถ', {
    hint: 'ยืนตรงท้ายรถ ให้เห็นกันชนหลังและป้ายทะเบียน',
  }),
  slot('EXT_LEFT', AROUND, 'ด้านซ้ายและประตูซ้าย', {
    hint: 'ถ่ายเต็มคันจากฝั่งซ้าย ให้เห็นประตูทุกบาน',
  }),
  slot('EXT_RIGHT', AROUND, 'ด้านขวาและประตูขวา', {
    hint: 'ถ่ายเต็มคันจากฝั่งขวา ให้เห็นประตูทุกบาน',
  }),

  slot('PILLAR_L', STRUCTURE, 'เสา A/B/C ฝั่งซ้าย', {
    maxPhotos: 3,
    hint: 'เปิดประตู ถ่ายเสาให้เห็นรอยเชื่อม/ซีลเดิม',
  }),
  slot('PILLAR_R', STRUCTURE, 'เสา A/B/C ฝั่งขวา', {
    maxPhotos: 3,
    hint: 'เปิดประตู ถ่ายเสาให้เห็นรอยเชื่อม/ซีลเดิม',
  }),

  slot('ENGINE_BAY', ENGINE_DOCS, 'ห้องเครื่อง', {
    hint: 'เปิดฝากระโปรง ถ่ายภาพรวมห้องเครื่อง',
  }),
  slot('VIN', ENGINE_DOCS, 'เลขตัวถัง (VIN)', {
    maxPhotos: 1,
    hint: 'ถ่ายให้อ่านเลขได้ชัดทุกตัว',
  }),
  slot('ODOMETER', ENGINE_DOCS, 'หน้าปัดเลขไมล์', {
    maxPhotos: 1,
    hint: 'ติดเครื่องแล้วถ่ายให้เห็นเลขไมล์และไฟเตือน',
  }),

  slot('CABIN', CABIN_GROUP, 'ภายในห้องโดยสาร', {
    hint: 'คอนโซลหน้า พวงมาลัย และเบาะ',
  }),
  slot('CARPET', CABIN_GROUP, 'ใต้พรม/ร่องรอยน้ำ', {
    required: false,
    hint: 'ถ่ายเมื่อสงสัยรถจมน้ำ',
  }),

  slot('DEFECTS', DEFECT, 'รูปตำหนิ', {
    required: false,
    maxPhotos: 20,
    captionRequired: true,
    hint: 'ถ่ายใกล้ ๆ ทีละจุด แล้วระบุตำแหน่งและอาการ เช่น "กันชนหน้าขวา รอยถลอก"',
  }),
];

export function findPhotoSlot(code: string): PhotoSlot | undefined {
  return PHOTO_SLOTS.find((s) => s.code === code);
}

export interface PhotoInput {
  slotCode: string;
  url: string;
  caption?: string | null;
}

/** ช่องที่ยังขาดรูป และรูปตำหนิที่ยังไม่มีคำอธิบาย ใช้ตรวจก่อนส่งรายงาน */
export function photoProblems(photos: PhotoInput[]): {
  missingSlots: string[];
  uncaptioned: number;
} {
  const count = new Map<string, number>();
  let uncaptioned = 0;
  for (const photo of photos) {
    count.set(photo.slotCode, (count.get(photo.slotCode) ?? 0) + 1);
    const def = findPhotoSlot(photo.slotCode);
    if (def?.captionRequired && !photo.caption?.trim()) uncaptioned += 1;
  }
  return {
    missingSlots: PHOTO_SLOTS.filter(
      (s) => s.required && !count.get(s.code),
    ).map((s) => s.label),
    uncaptioned,
  };
}
