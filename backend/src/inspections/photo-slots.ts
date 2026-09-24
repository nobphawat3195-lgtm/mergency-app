/**
 * ช่องภาพหลักฐานของงานตรวจรถมือสอง แยกเป็นหัวข้อตามมุมที่ต้องถ่าย
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
  maxPhotos: 3,
  ...options,
});

const EXTERIOR = 'ภายนอกรอบคัน';
const DOORS = 'ประตูและชิ้นส่วนตัวถัง';
const STRUCTURE = 'เสา A/B/C และโครงสร้าง';
const ENGINE = 'ห้องเครื่อง';
const DOCUMENTS = 'เอกสารและเลขตัวรถ';
const CABIN = 'ห้องโดยสาร';
const WHEELS = 'ยางและล้อ';
const SCAN = 'ผลสแกน OBD';
const DEFECT = 'ตำหนิที่พบ';

export const PHOTO_SLOTS: PhotoSlot[] = [
  slot('EXT_FRONT', EXTERIOR, 'ด้านหน้าตรง', { maxPhotos: 2 }),
  slot('EXT_REAR', EXTERIOR, 'ด้านหลังตรง', { maxPhotos: 2 }),
  slot('EXT_LEFT', EXTERIOR, 'ด้านซ้ายเต็มคัน', { maxPhotos: 2 }),
  slot('EXT_RIGHT', EXTERIOR, 'ด้านขวาเต็มคัน', { maxPhotos: 2 }),

  slot('DOOR_FL', DOORS, 'ประตูหน้าซ้าย', {
    hint: 'ถ่ายด้านนอก และเปิดประตูถ่ายขอบประตู/ยางขอบประตู',
  }),
  slot('DOOR_RL', DOORS, 'ประตูหลังซ้าย', {
    required: false,
    hint: 'ข้ามได้ถ้ารถไม่มีประตูหลัง',
  }),
  slot('DOOR_FR', DOORS, 'ประตูหน้าขวา', {
    hint: 'ถ่ายด้านนอก และเปิดประตูถ่ายขอบประตู/ยางขอบประตู',
  }),
  slot('DOOR_RR', DOORS, 'ประตูหลังขวา', {
    required: false,
    hint: 'ข้ามได้ถ้ารถไม่มีประตูหลัง',
  }),
  slot('HOOD', DOORS, 'ฝากระโปรงหน้า'),
  slot('TRUNK', DOORS, 'ฝาท้าย/กระบะท้าย'),
  slot('ROOF', DOORS, 'หลังคา', { required: false, maxPhotos: 2 }),

  slot('PILLAR_L', STRUCTURE, 'เสา A/B/C ฝั่งซ้าย', {
    hint: 'เปิดประตูถ่ายเสาทั้ง 3 ต้น ให้เห็นรอยเชื่อม/ซีลเดิม',
  }),
  slot('PILLAR_R', STRUCTURE, 'เสา A/B/C ฝั่งขวา', {
    hint: 'เปิดประตูถ่ายเสาทั้ง 3 ต้น ให้เห็นรอยเชื่อม/ซีลเดิม',
  }),
  slot('FRONT_BEAM', STRUCTURE, 'คานหน้าและแผงหม้อน้ำ'),
  slot('REAR_FLOOR', STRUCTURE, 'พื้นท้ายและใต้พรมห้องสัมภาระ'),

  slot('ENGINE_BAY', ENGINE, 'ห้องเครื่องภาพรวม', { maxPhotos: 4 }),
  slot('ENGINE_NO', ENGINE, 'เลขเครื่องยนต์', { maxPhotos: 2 }),

  slot('VIN', DOCUMENTS, 'เลขตัวถังบนตัวรถ', { maxPhotos: 2 }),
  slot('ODOMETER', DOCUMENTS, 'หน้าปัดเลขไมล์ขณะติดเครื่อง', { maxPhotos: 2 }),
  slot('REG_BOOK', DOCUMENTS, 'เล่มทะเบียน หน้ารายการจดทะเบียน', {
    hint: 'บังเลขบัตรประชาชนของเจ้าของเดิมก่อนถ่าย',
  }),

  slot('CABIN_FRONT', CABIN, 'คอนโซลหน้าและพวงมาลัย'),
  slot('CABIN_REAR', CABIN, 'เบาะหลัง', { required: false }),
  slot('CARPET', CABIN, 'ใต้พรม/ร่องรอยน้ำ', { required: false }),

  slot('TIRES', WHEELS, 'ยางทั้ง 4 ล้อ', {
    maxPhotos: 5,
    hint: 'ล้อละ 1 รูป ให้เห็นดอกยางและรหัส DOT ถ้าทำได้',
  }),

  slot('OBD_SCAN', SCAN, 'หน้าจอผลสแกน OBD', { maxPhotos: 4 }),

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
