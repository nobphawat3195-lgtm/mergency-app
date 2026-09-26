/**
 * รายการตรวจรถมือสองก่อนซื้อ (Pre-purchase inspection) ของ FixGo
 *
 * เป็นแหล่งข้อมูลเดียวของทั้งระบบ: แอปช่างดึงไปแสดงเป็นแบบฟอร์ม, backend ใช้คำนวณคะแนน,
 * แอปลูกค้าใช้แสดงรายงาน ถ้าเพิ่ม/ลบ/เปลี่ยนความหมายของข้อใด ต้องเพิ่ม CHECKLIST_VERSION
 * เพื่อให้รายงานเก่ายังอ่านได้ตามเวอร์ชันที่ตรวจจริง
 *
 * อ้างอิงแนวทางตรวจจากผู้ให้บริการตรวจรถมือสองในไทย (ตรวจ 150–274 จุด) และคู่มือ
 * ดูรถน้ำท่วม/รถชนหนัก/เลขไมล์ เน้น 3 ความเสี่ยงหลักที่ผู้ซื้อกลัวที่สุด:
 * รถจมน้ำ, รถชนหนักโครงสร้างเสียหาย, และการกรอเลขไมล์
 */

export const CHECKLIST_VERSION = 1;

/** ความเสี่ยงหลักที่รายงานสรุปแยกให้ผู้ซื้อเห็นชัด */
export type RiskFlag = 'flood' | 'accident' | 'odometer' | 'legal';

/** ข้อที่ใช้กับรถบางแบบเท่านั้น */
export type AppliesTo =
  | 'all'
  | 'combustion'
  | 'electrified'
  | 'manual'
  | 'automatic';

export interface MeasurementRule {
  unit: string;
  /** ค่ามากกว่าเท่ากับค่านี้ = ผ่าน (ใช้กับค่าที่ยิ่งมากยิ่งดี เช่น ดอกยาง) */
  passMin?: number;
  attentionMin?: number;
  /** ค่าน้อยกว่าเท่ากับค่านี้ = ผ่าน (ใช้กับค่าที่ยิ่งน้อยยิ่งดี เช่น ความหนาสี) */
  passMax?: number;
  attentionMax?: number;
}

export interface ChecklistItem {
  code: string;
  label: string;
  /** คำแนะนำสั้น ๆ ให้ช่างตรวจแบบเดียวกันทุกคน */
  hint?: string;
  /** ข้อสำคัญ: ถ้าไม่ผ่านถือว่ามีความเสี่ยงสูง ผลสรุปจะเป็น "ไม่แนะนำให้ซื้อ" */
  critical?: boolean;
  flags?: RiskFlag[];
  appliesTo?: AppliesTo;
  measurement?: MeasurementRule;
  /** ต้องมีรูปประกอบเมื่อผลไม่ผ่าน/ควรระวัง */
  photoOnIssue?: boolean;
}

export interface ChecklistSection {
  code: string;
  title: string;
  description: string;
  items: ChecklistItem[];
}

const PAINT: MeasurementRule = {
  unit: 'ไมครอน',
  passMax: 180,
  attentionMax: 300,
};

const TREAD: MeasurementRule = { unit: 'มม.', passMin: 3, attentionMin: 1.6 };

const paintPanel = (code: string, label: string): ChecklistItem => ({
  code,
  label: `ความหนาสี ${label}`,
  hint: 'วัดด้วยเครื่องวัดความหนาสี 3 จุดต่อชิ้น บันทึกค่าสูงสุด เกิน 180 = น่าจะทำสี เกิน 300 = น่าจะโป๊วสี',
  flags: ['accident'],
  measurement: PAINT,
  photoOnIssue: true,
});

const tire = (code: string, label: string): ChecklistItem => ({
  code,
  label: `ความลึกดอกยาง ${label}`,
  hint: 'วัดร่องกลางดอกยาง ต่ำกว่า 1.6 มม. ผิดกฎหมาย ควรเปลี่ยน',
  measurement: TREAD,
});

export const CHECKLIST: ChecklistSection[] = [
  {
    code: 'DOC',
    title: 'เอกสารและตัวตนรถ',
    description:
      'ยืนยันว่ารถคันนี้ตรงกับเล่มทะเบียน ไม่ใช่รถขโมยหรือรถสวมทะเบียน',
    items: [
      {
        code: 'DOC01',
        label: 'เล่มทะเบียนตัวจริง ชื่อผู้ครอบครองตรงกับผู้ขาย',
        critical: true,
        flags: ['legal'],
      },
      {
        code: 'DOC02',
        label: 'เลขตัวถัง (VIN) ที่ตัวรถตรงกับเล่มทะเบียน',
        critical: true,
        flags: ['legal'],
        photoOnIssue: true,
      },
      {
        code: 'DOC03',
        label: 'เลขเครื่องยนต์ตรงกับเล่มทะเบียน',
        critical: true,
        flags: ['legal'],
        appliesTo: 'combustion',
        photoOnIssue: true,
      },
      {
        code: 'DOC04',
        label: 'ไม่มีร่องรอยขูดลบหรือตอกเลขตัวถัง/เลขเครื่องใหม่',
        critical: true,
        flags: ['legal', 'accident'],
        photoOnIssue: true,
      },
      {
        code: 'DOC05',
        label: 'สี ยี่ห้อ รุ่น ในเล่มตรงกับตัวรถ (หรือมีบันทึกเปลี่ยนสี)',
        flags: ['legal'],
      },
      {
        code: 'DOC06',
        label: 'ประวัติการเปลี่ยนเครื่อง/เปลี่ยนสีในเล่มมีบันทึกถูกต้อง',
        flags: ['legal'],
      },
      {
        code: 'DOC07',
        label: 'ภาษีรถยนต์และ พ.ร.บ. ยังไม่ขาด',
        hint: 'ดูป้ายวงกลมและวันหมดอายุ',
      },
      {
        code: 'DOC08',
        label: 'ไม่ติดภาระไฟแนนซ์ หรือมีหนังสือยืนยันยอดปิดบัญชี',
        flags: ['legal'],
      },
      { code: 'DOC09', label: 'จำนวนผู้ครอบครองมือก่อน ๆ สมเหตุสมผลกับอายุรถ' },
      {
        code: 'DOC10',
        label: 'มีสมุดประวัติเข้าศูนย์/ใบเสร็จเช็กระยะ',
        flags: ['odometer'],
      },
      { code: 'DOC11', label: 'กุญแจ/รีโมตครบ 2 ดอก และใช้งานได้' },
      {
        code: 'DOC12',
        label: 'ป้ายทะเบียนหน้า-หลังตรงกับเล่ม ไม่มีร่องรอยงัดแงะ',
        flags: ['legal'],
      },
      {
        code: 'DOC13',
        label: 'ใบวิศวะรับรองการติดตั้ง (กรณีติดแก๊ส LPG/NGV)',
        appliesTo: 'combustion',
      },
    ],
  },
  {
    code: 'FRM',
    title: 'โครงสร้างตัวถังและประวัติอุบัติเหตุ',
    description: 'ตรวจจุดโครงสร้างที่ถ้าเสียหายแล้วซ่อมกลับมาไม่เหมือนเดิม',
    items: [
      {
        code: 'FRM01',
        label: 'คานหน้า/แชสซีด้านหน้า ไม่มีรอยดัด เชื่อม หรือตัดต่อ',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM02',
        label:
          'แผงหน้ารถ (คานรับหม้อน้ำ) เป็นของเดิม หมุด/รอยเชื่อมจุดไม่ถูกแต่ง',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM03',
        label: 'ซุ้มล้อหน้าซ้าย-ขวา ไม่มีรอยดึงหรือรอยเชื่อม',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM04',
        label: 'เสา A ซ้าย-ขวา ไม่มีรอยซ่อม',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM05',
        label: 'เสา B ซ้าย-ขวา ไม่มีรอยซ่อม',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM06',
        label: 'เสา C/หลังคาไม่มีรอยตัดต่อ',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM07',
        label: 'ขอบประตูและยางขอบประตู ซีลเลอร์เป็นลายเดิมจากโรงงาน',
        flags: ['accident'],
      },
      {
        code: 'FRM08',
        label: 'พื้นห้องโดยสารและคานใต้ท้องรถไม่ยุบ ไม่มีรอยเชื่อม',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM09',
        label: 'พื้นห้องสัมภาระ/หลุมยางอะไหล่ไม่มีรอยดึงหรือเชื่อม',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM10',
        label: 'คานหลังและแชสซีด้านหลังไม่คด',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
      {
        code: 'FRM11',
        label: 'น็อตยึดบังโคลน ฝากระโปรง ประตู ไม่มีรอยขัน (สีบนหัวน็อตไม่แตก)',
        flags: ['accident'],
      },
      {
        code: 'FRM12',
        label: 'ถุงลมนิรภัยไม่เคยระเบิด (ฝาครอบพวงมาลัย/คอนโซลเป็นของเดิม)',
        critical: true,
        flags: ['accident'],
        photoOnIssue: true,
      },
    ],
  },
  {
    code: 'PNT',
    title: 'สีและตัวถังภายนอก',
    description: 'วัดความหนาสีทุกชิ้นเพื่อหาชิ้นที่เคยทำสีหรือโป๊ว',
    items: [
      paintPanel('PNT01', 'ฝากระโปรงหน้า'),
      paintPanel('PNT02', 'หลังคา'),
      paintPanel('PNT03', 'ฝากระโปรงท้าย'),
      paintPanel('PNT04', 'บังโคลนหน้าซ้าย'),
      paintPanel('PNT05', 'บังโคลนหน้าขวา'),
      paintPanel('PNT06', 'ประตูหน้าซ้าย'),
      paintPanel('PNT07', 'ประตูหน้าขวา'),
      paintPanel('PNT08', 'ประตูหลังซ้าย'),
      paintPanel('PNT09', 'ประตูหลังขวา'),
      paintPanel('PNT10', 'แก้มท้ายซ้าย'),
      paintPanel('PNT11', 'แก้มท้ายขวา'),
      {
        code: 'PNT12',
        label: 'ร่องรอยต่อชิ้นส่วน (panel gap) เท่ากันทั้งคัน',
        flags: ['accident'],
      },
      {
        code: 'PNT13',
        label: 'สีทุกชิ้นเฉดเดียวกัน ไม่มีสีเหลื่อม/ละอองสีเกาะยาง',
        flags: ['accident'],
      },
      {
        code: 'PNT14',
        label: 'ไม่มีสนิม ผุ หรือบวมใต้สี (ขอบประตู ซุ้มล้อ ใต้ธรณีประตู)',
        flags: ['flood'],
      },
      {
        code: 'PNT15',
        label:
          'กระจกทุกบานรหัสปีผลิตใกล้เคียงกัน (ถ้าเปลี่ยนบานไหนต้องมีเหตุผล)',
        flags: ['accident'],
      },
      {
        code: 'PNT16',
        label: 'โคมไฟหน้า-ท้ายไม่แตกร้าว ไม่มีฝ้า/น้ำขัง',
        flags: ['flood'],
      },
      { code: 'PNT17', label: 'กันชนหน้า-หลังไม่แตก ยึดแน่น' },
    ],
  },
  {
    code: 'FLD',
    title: 'ตรวจร่องรอยรถจมน้ำ',
    description:
      'รถน้ำท่วมมักมีปัญหาไฟฟ้าและสนิมตามมาทีหลัง ตรวจทุกจุดที่น้ำและโคลนซ่อนอยู่',
    items: [
      {
        code: 'FLD01',
        label: 'ใต้พรมและใต้เบาะไม่มีคราบโคลน ทราย หรือเส้นระดับน้ำ',
        critical: true,
        flags: ['flood'],
        photoOnIssue: true,
      },
      {
        code: 'FLD02',
        label: 'ไม่มีกลิ่นอับชื้นในห้องโดยสาร/ห้องสัมภาระ',
        flags: ['flood'],
      },
      {
        code: 'FLD03',
        label: 'รางเบาะ น็อตยึดเบาะ และขาเบาะไม่เป็นสนิม',
        critical: true,
        flags: ['flood'],
        photoOnIssue: true,
      },
      {
        code: 'FLD04',
        label: 'ดึงเข็มขัดนิรภัยจนสุด ไม่มีคราบน้ำ/โคลน',
        flags: ['flood'],
      },
      {
        code: 'FLD05',
        label: 'ขั้วปลั๊ก ข้อต่อสายไฟใต้คอนโซลและใต้เบาะไม่มีสนิมเขียว',
        critical: true,
        flags: ['flood'],
        photoOnIssue: true,
      },
      {
        code: 'FLD06',
        label: 'กล่อง ECU/ฟิวส์บ็อกซ์ไม่มีคราบน้ำหรือสนิม',
        critical: true,
        flags: ['flood'],
        photoOnIssue: true,
      },
      {
        code: 'FLD07',
        label: 'หลุมยางอะไหล่และใต้พรมท้ายแห้ง ไม่มีตะกอน',
        flags: ['flood'],
        photoOnIssue: true,
      },
      {
        code: 'FLD08',
        label: 'ในแผงประตูและลำโพงไม่มีคราบโคลน',
        flags: ['flood'],
      },
      {
        code: 'FLD09',
        label: 'ใต้ท้องรถ ถังน้ำมัน ท่อไอเสีย ไม่มีสนิมผิดปกติเทียบกับอายุรถ',
        flags: ['flood'],
      },
      {
        code: 'FLD10',
        label: 'ไส้กรองอากาศห้องเครื่องและกรองแอร์ไม่มีคราบน้ำ/ตะกอน',
        flags: ['flood'],
      },
    ],
  },
  {
    code: 'ENG',
    title: 'ห้องเครื่องยนต์',
    description: 'ตรวจตอนเครื่องเย็นก่อนสตาร์ท แล้วฟังเสียงตอนสตาร์ทครั้งแรก',
    items: [
      {
        code: 'ENG01',
        label: 'สตาร์ทเครื่องเย็นติดง่าย ไม่มีเสียงผิดปกติ',
        critical: true,
        appliesTo: 'combustion',
      },
      {
        code: 'ENG02',
        label: 'รอบเดินเบานิ่ง เครื่องไม่สั่นผิดปกติ',
        appliesTo: 'combustion',
      },
      {
        code: 'ENG03',
        label: 'ไม่มีเสียงเคาะ/เสียงวาล์วดังผิดปกติ',
        critical: true,
        appliesTo: 'combustion',
      },
      {
        code: 'ENG04',
        label: 'ควันไอเสียปกติ (ไม่มีควันขาว ดำ หรือน้ำเงินต่อเนื่อง)',
        critical: true,
        appliesTo: 'combustion',
      },
      {
        code: 'ENG05',
        label: 'น้ำมันเครื่องสีปกติ ไม่ขุ่นเป็นสีกาแฟใส่นม (น้ำปน)',
        critical: true,
        flags: ['flood'],
        appliesTo: 'combustion',
        photoOnIssue: true,
      },
      {
        code: 'ENG06',
        label: 'ใต้ฝาเติมน้ำมันเครื่องไม่มีคราบครีมขาว (ปะเก็นฝาสูบ)',
        critical: true,
        appliesTo: 'combustion',
      },
      {
        code: 'ENG07',
        label: 'ไม่มีน้ำมันรั่วซึมรอบเครื่อง ฝาวาล์ว อ่างน้ำมัน',
        appliesTo: 'combustion',
        photoOnIssue: true,
      },
      {
        code: 'ENG08',
        label: 'น้ำหล่อเย็นระดับปกติ ไม่มีคราบน้ำมันลอย',
        critical: true,
        appliesTo: 'combustion',
      },
      {
        code: 'ENG09',
        label: 'หม้อน้ำ ท่อยางหม้อน้ำไม่รั่ว ไม่บวม',
        appliesTo: 'combustion',
      },
      {
        code: 'ENG10',
        label: 'สายพานหน้าเครื่องไม่แตกลาย ไม่มีเสียงดัง',
        appliesTo: 'combustion',
      },
      {
        code: 'ENG11',
        label: 'ยางแท่นเครื่องไม่ขาด (ดูตอนเข้าเกียร์ D/R เครื่องไม่โยก)',
      },
      {
        code: 'ENG12',
        label: 'ห้องเครื่องไม่ถูกล้างหรือพ่นสีดำจนผิดปกติ (อาจปิดรอยรั่ว)',
      },
      {
        code: 'ENG13',
        label: 'ระบบเชื้อเพลิงไม่มีกลิ่นหรือรอยรั่วซึม',
        critical: true,
        appliesTo: 'combustion',
      },
      {
        code: 'ENG14',
        label: 'แรงดันแบตเตอรี่ 12V ขณะดับเครื่อง',
        hint: 'ต่ำกว่า 12.2V แบตใกล้หมดอายุ',
        measurement: { unit: 'โวลต์', passMin: 12.4, attentionMin: 12.2 },
      },
      {
        code: 'ENG15',
        label: 'แรงดันไฟชาร์จขณะติดเครื่อง (ไดชาร์จ)',
        hint: 'ปกติ 13.8–14.7V',
        appliesTo: 'combustion',
        measurement: { unit: 'โวลต์', passMin: 13.6, attentionMin: 13.2 },
      },
      {
        code: 'ENG16',
        label: 'น้ำมันเกียร์/น้ำมันเพาเวอร์สีและกลิ่นปกติ ไม่ไหม้',
      },
      { code: 'ENG17', label: 'น้ำมันเบรกระดับปกติ สีไม่ดำคล้ำ' },
      {
        code: 'ENG18',
        label: 'ความชื้นในน้ำมันเบรก',
        hint: 'วัดด้วยปากกาวัดน้ำมันเบรก เกิน 3% ควรเปลี่ยน',
        measurement: { unit: '%', passMax: 2, attentionMax: 3 },
      },
    ],
  },
  {
    code: 'OBD',
    title: 'สแกนคอมพิวเตอร์ (OBD2)',
    description: 'อ่านโค้ดปัญหาและเทียบเลขไมล์ในกล่องกับหน้าปัด',
    items: [
      {
        code: 'OBD01',
        label: 'ไม่มีโค้ดปัญหาปัจจุบัน (Active DTC) ในระบบเครื่องยนต์/เกียร์',
        critical: true,
        photoOnIssue: true,
      },
      {
        code: 'OBD02',
        label: 'Readiness monitors ครบ (ถ้าไม่ครบ อาจเพิ่งลบโค้ดก่อนขาย)',
        flags: ['odometer'],
      },
      {
        code: 'OBD03',
        label: 'เลขไมล์ในกล่อง ECU/ABS ตรงกับหน้าปัด',
        critical: true,
        flags: ['odometer'],
        photoOnIssue: true,
      },
      {
        code: 'OBD04',
        label: 'ระบบถุงลมนิรภัย (SRS) ไม่มีโค้ด',
        critical: true,
        flags: ['accident'],
      },
      { code: 'OBD05', label: 'ระบบ ABS/ESP/เบรกไม่มีโค้ด' },
      {
        code: 'OBD06',
        label: 'ระบบเกียร์อัตโนมัติไม่มีโค้ด',
        appliesTo: 'automatic',
      },
      {
        code: 'OBD07',
        label: 'ระบบไฟฟ้าตัวถัง (BCM) และแอร์ไม่มีโค้ด',
        flags: ['flood'],
      },
    ],
  },
  {
    code: 'EV',
    title: 'ระบบไฮบริด/ไฟฟ้า (EV, HEV, PHEV)',
    description: 'แบตเตอรี่แรงดันสูงเป็นชิ้นส่วนที่แพงที่สุดของรถไฟฟ้า',
    items: [
      {
        code: 'EV01',
        label: 'สุขภาพแบตเตอรี่แรงดันสูง (SOH)',
        hint: 'อ่านจากเครื่องสแกนหรือแอปของยี่ห้อ',
        critical: true,
        appliesTo: 'electrified',
        measurement: { unit: '%', passMin: 90, attentionMin: 80 },
      },
      {
        code: 'EV02',
        label: 'ระยะวิ่งที่แสดงเมื่อชาร์จเต็มสมเหตุสมผลกับสเปก',
        appliesTo: 'electrified',
      },
      {
        code: 'EV03',
        label: 'ไม่มีไฟเตือนระบบไฟฟ้าแรงสูง/ระบบไฮบริด',
        critical: true,
        appliesTo: 'electrified',
      },
      {
        code: 'EV04',
        label: 'ช่องชาร์จ AC/DC ไม่ไหม้ ไม่หลวม ล็อกหัวชาร์จได้',
        appliesTo: 'electrified',
      },
      {
        code: 'EV05',
        label: 'สายไฟแรงสูง (สีส้ม) ไม่ฉีกขาด ไม่มีรอยกระแทกที่แพ็กแบต',
        critical: true,
        flags: ['accident'],
        appliesTo: 'electrified',
        photoOnIssue: true,
      },
      {
        code: 'EV06',
        label: 'ระบบระบายความร้อนแบต (พัดลม/น้ำหล่อเย็น) ทำงานปกติ',
        appliesTo: 'electrified',
      },
      {
        code: 'EV07',
        label: 'สายชาร์จพกพา/อุปกรณ์ชาร์จที่มากับรถครบและใช้งานได้',
        appliesTo: 'electrified',
      },
      {
        code: 'EV08',
        label: 'ประกันแบตเตอรี่จากศูนย์ยังเหลือ/โอนสิทธิ์ได้',
        appliesTo: 'electrified',
      },
    ],
  },
  {
    code: 'SUS',
    title: 'ช่วงล่าง พวงมาลัย และเบรก',
    description: 'ยกรถหรือส่องใต้ท้อง ตรวจการรั่วซึมและความหลวมของชิ้นส่วน',
    items: [
      { code: 'SUS01', label: 'โช้คอัพหน้าไม่รั่วซึม กดแล้วคืนตัวปกติ' },
      { code: 'SUS02', label: 'โช้คอัพหลังไม่รั่วซึม' },
      { code: 'SUS03', label: 'ลูกหมากปีกนก/คันชัก/แร็คไม่หลวม' },
      { code: 'SUS04', label: 'บูชปีกนกและยางกันโคลงไม่แตก' },
      { code: 'SUS05', label: 'ยางหุ้มเพลาขับไม่ฉีก ไม่มีจาระบีกระเด็น' },
      {
        code: 'SUS06',
        label: 'แร็คพวงมาลัย/ปั๊มเพาเวอร์ไม่รั่ว ระยะฟรีพวงมาลัยปกติ',
      },
      {
        code: 'SUS07',
        label: 'ความหนาผ้าเบรกหน้า',
        measurement: { unit: 'มม.', passMin: 4, attentionMin: 2.5 },
      },
      {
        code: 'SUS08',
        label: 'ความหนาผ้าเบรกหลัง',
        measurement: { unit: 'มม.', passMin: 4, attentionMin: 2.5 },
      },
      { code: 'SUS09', label: 'จานเบรกไม่เป็นร่องลึก ไม่คด' },
      { code: 'SUS10', label: 'เบรกมือ/เบรกไฟฟ้าล็อกรถได้บนทางลาด' },
      {
        code: 'SUS11',
        label: 'ท่อไอเสียและขายึดไม่รั่ว ไม่หลุด',
        appliesTo: 'combustion',
      },
    ],
  },
  {
    code: 'TIR',
    title: 'ยางและล้อ',
    description: 'ดอกยางสึกไม่เท่ากันบอกปัญหาศูนย์ล้อหรือช่วงล่างคด',
    items: [
      tire('TIR01', 'หน้าซ้าย'),
      tire('TIR02', 'หน้าขวา'),
      tire('TIR03', 'หลังซ้าย'),
      tire('TIR04', 'หลังขวา'),
      {
        code: 'TIR05',
        label: 'ดอกยางสึกเท่ากันทั้งหน้ายาง (ไม่กินขอบข้างเดียว)',
        flags: ['accident'],
      },
      {
        code: 'TIR06',
        label: 'ปีผลิตยาง (รหัส DOT) ไม่เกิน 5 ปี',
        hint: 'ตัวเลข 4 หลักท้าย เช่น 2423 = สัปดาห์ 24 ปี 2023',
      },
      { code: 'TIR07', label: 'แก้มยางไม่บวม ไม่ฉีก' },
      {
        code: 'TIR08',
        label: 'ล้อแม็กไม่บิ่น ไม่คด ไม่มีรอยเชื่อม',
        flags: ['accident'],
      },
      { code: 'TIR09', label: 'ยางอะไหล่ แม่แรง และประแจครบ' },
    ],
  },
  {
    code: 'INT',
    title: 'ห้องโดยสารและระบบไฟฟ้า',
    description: 'ความสึกหรอภายในต้องสอดคล้องกับเลขไมล์',
    items: [
      {
        code: 'INT01',
        label:
          'ไฟเตือนบนหน้าปัดดับหมดหลังสตาร์ท (เช็กว่าหลอดไฟเตือนติดตอนเปิดสวิตช์)',
        critical: true,
      },
      {
        code: 'INT02',
        label: 'ความสึกของพวงมาลัย หัวเกียร์ แป้นเบรก สอดคล้องกับเลขไมล์',
        flags: ['odometer'],
      },
      {
        code: 'INT03',
        label: 'เบาะคนขับ (ขอบเบาะ) สึกสอดคล้องกับเลขไมล์',
        flags: ['odometer'],
      },
      {
        code: 'INT04',
        label: 'อุณหภูมิลมแอร์ที่ช่องกลาง (เปิดสุด 5 นาที)',
        hint: 'ปกติ 4–8 องศา',
        measurement: { unit: '°C', passMax: 8, attentionMax: 11 },
      },
      {
        code: 'INT05',
        label: 'พัดลมแอร์ปรับได้ทุกระดับ ไม่มีกลิ่นอับ',
        flags: ['flood'],
      },
      { code: 'INT06', label: 'กระจกไฟฟ้าทำงานครบทุกบาน' },
      { code: 'INT07', label: 'เซ็นทรัลล็อกและรีโมตทำงาน' },
      { code: 'INT08', label: 'กระจกมองข้างปรับ/พับไฟฟ้าได้' },
      {
        code: 'INT09',
        label: 'ไฟหน้าต่ำ-สูง ไฟตัดหมอก ไฟเลี้ยว ไฟผ่าหมาก ทำงาน',
      },
      { code: 'INT10', label: 'ไฟเบรก ไฟถอย ไฟส่องป้ายทะเบียน ทำงาน' },
      { code: 'INT11', label: 'แตร ที่ปัดน้ำฝน และหัวฉีดน้ำทำงาน' },
      { code: 'INT12', label: 'เครื่องเสียง จอ กล้องถอย และเซ็นเซอร์ถอยทำงาน' },
      { code: 'INT13', label: 'เข็มขัดนิรภัยทุกตำแหน่งดึงและล็อกได้' },
      { code: 'INT14', label: 'เบาะปรับได้ครบทุกทิศทาง' },
      {
        code: 'INT15',
        label: 'ซันรูฟ/หลังคาเปิดได้ ไม่มีน้ำซึม (ถ้ามี)',
        flags: ['flood'],
      },
      { code: 'INT16', label: 'ช่อง USB/ที่จุดบุหรี่/ปลั๊กชาร์จใช้งานได้' },
      {
        code: 'INT17',
        label: 'ผ้าหลังคาไม่มีคราบน้ำหรือรอยย้วย',
        flags: ['flood'],
      },
    ],
  },
  {
    code: 'DRV',
    title: 'ทดลองขับ',
    description:
      'ขับอย่างน้อย 10 นาที ครอบคลุมความเร็วต่ำ ความเร็วสูง และการเบรกแรง',
    items: [
      { code: 'DRV01', label: 'ออกตัวนุ่ม ไม่มีอาการสะดุด', critical: true },
      {
        code: 'DRV02',
        label: 'เกียร์อัตโนมัติเปลี่ยนนุ่ม ไม่กระตุก ไม่ลาก ไม่ดีเลย์',
        critical: true,
        appliesTo: 'automatic',
      },
      {
        code: 'DRV03',
        label: 'คลัตช์จับปกติ ไม่ลื่น ไม่มีเสียงลูกปืน',
        critical: true,
        appliesTo: 'manual',
      },
      {
        code: 'DRV04',
        label: 'เร่งแซงมีกำลัง รอบไม่ลอย',
        appliesTo: 'combustion',
      },
      {
        code: 'DRV05',
        label: 'พวงมาลัยตรงเมื่อปล่อยมือ รถไม่ดึงซ้าย/ขวา',
        flags: ['accident'],
      },
      {
        code: 'DRV06',
        label: 'เบรกแรงแล้วรถไม่ปัด ไม่สั่น ไม่มีเสียงดัง',
        critical: true,
      },
      { code: 'DRV07', label: 'ไม่มีเสียงดังจากช่วงล่างเมื่อผ่านทางขรุขระ' },
      { code: 'DRV08', label: 'ไม่มีเสียงหอน/เสียงลูกปืนล้อที่ความเร็วสูง' },
      { code: 'DRV09', label: 'ไม่สั่นที่ความเร็ว 80–110 กม./ชม.' },
      {
        code: 'DRV10',
        label: 'เข็มความร้อนคงที่ตลอดการขับ',
        critical: true,
        appliesTo: 'combustion',
      },
      { code: 'DRV11', label: 'ครูสคอนโทรลและระบบช่วยขับ (ถ้ามี) ทำงาน' },
      { code: 'DRV12', label: 'หลังขับไม่มีน้ำมัน/น้ำหยดใต้รถ' },
    ],
  },
];

export function allChecklistItems(): ChecklistItem[] {
  return CHECKLIST.flatMap((section) => section.items);
}

export function findChecklistItem(code: string): ChecklistItem | undefined {
  return allChecklistItems().find((item) => item.code === code);
}
