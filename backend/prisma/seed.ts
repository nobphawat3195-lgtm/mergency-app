import 'dotenv/config';
import { PrismaClient, PriceType } from '@prisma/client';

const prisma = new PrismaClient();

/** ราคาเก็บเป็นสตางค์ */
const baht = (amount: number): number => amount * 100;

/**
 * ราคาเท่ากันทุกประเภทรถ (เจ้าของกำหนด ก.ย. 2569) ตัวคูณจึงเป็น 1 ทั้งหมด
 * เก็บคอลัมน์ multiplier ไว้เผื่ออยากกลับมาคิดราคาตามขนาดรถภายหลัง
 */
const VEHICLE_TYPES = [
  { slug: 'sedan', name: 'รถเก๋ง', multiplier: 1, sortOrder: 1 },
  { slug: 'suv', name: 'รถ SUV', multiplier: 1, sortOrder: 2 },
  { slug: 'pickup', name: 'รถกระบะ', multiplier: 1, sortOrder: 3 },
  { slug: 'van', name: 'รถตู้', multiplier: 1, sortOrder: 4 },
  { slug: 'motorcycle', name: 'มอเตอร์ไซค์', multiplier: 1, sortOrder: 5 },
  { slug: 'ev', name: 'รถ EV', multiplier: 1, sortOrder: 6 },
  { slug: 'euro', name: 'รถยุโรป', multiplier: 1, sortOrder: 7 },
  { slug: 'truck', name: 'รถบรรทุก', multiplier: 1, sortOrder: 8 },
  { slug: 'machinery', name: 'เครื่องจักร', multiplier: 1, sortOrder: 9 },
];

/** ข้อความมาตรฐาน: ราคาในแอปเป็นค่าแรงเริ่มต้น ช่างแจ้งราคาจริงให้ลูกค้ายืนยันก่อนเริ่มงาน */
const LABOR_ONLY =
  'ค่าแรงเริ่มต้น ไม่รวมอะไหล่ ช่างแจ้งราคาจริงให้ยืนยันก่อนเริ่มงาน';

/**
 * อัตรารถสไลด์ที่ใช้กันทั่วไปในไทย (สำรวจ ก.ย. 2569): เริ่มต้น 1,500 บาทในระยะ 15 กม.
 * เกินจากนั้นประมาณ 20–30 บาท/กม. เจ้าของรถสไลด์ประเมินราคาจริงตามระยะทางอีกครั้ง
 */
const TOW_NOTE =
  'ราคา 1,500–5,000 บาท ขึ้นกับระยะทาง ขนาดรถ และสภาพหน้างาน ' +
  'เริ่มต้น 1,500 บาทรวมระยะทางประมาณ 15 กม. ถ้าไกลกว่านั้นคิดเพิ่มประมาณ 20–30 บาท/กม. ' +
  'เจ้าของรถสไลด์แจ้งราคาจริงให้คุณยืนยันก่อนยกรถเสมอ';

// ราคาทั้งหมดกำหนดโดยเจ้าของโปรเจกต์ (ก.ย. 2569) เป็นค่าแรงเริ่มต้น
// บริการที่ไม่อยู่ในรายการของเจ้าของใช้ค่าแรงเริ่มต้น 750 บาท
// ปรับรอบสอง: บวก 100 บาททุกบริการ ยกเว้นรถสไลด์ (1,500–5,000) และตรวจรถมือสอง (1,990)
const CATEGORIES = [
  {
    slug: 'car-mechanic',
    name: 'ช่างซ่อมรถยนต์',
    iconKey: 'mechanic',
    sortOrder: 1,
    subServices: [
      {
        name: 'เรียกช่างให้ไปดูก่อน จ่ายเงินหน้างาน',
        description:
          'ช่างไปวิเคราะห์อาการที่หน้างาน แล้วเสนอราคาซ่อมให้ยืนยันก่อน',
        basePrice: baht(750),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'เช็คโค้ด ไฟเตือนโชว์หน้าปัด',
        description: 'ช่างนำเครื่องอ่านโค้ดไปตรวจหาสาเหตุไฟเตือนที่หน้างาน',
        basePrice: baht(750),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'รถดับกลางทาง',
        description: 'ช่างไปดูอาการหน้างานและประเมินเบื้องต้น',
        basePrice: baht(750),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'รถสตาร์ทไม่ติด',
        description: 'ช่างไปดูอาการหน้างานและประเมินเบื้องต้น',
        basePrice: baht(750),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'ซ่อมนอกสถานที่',
        description: LABOR_ONLY,
        basePrice: baht(750),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  {
    slug: 'alternator-electrical',
    name: 'ไดนาโม ระบบไฟ',
    iconKey: 'electrical',
    sortOrder: 2,
    subServices: [
      {
        name: 'เรียกช่างให้ไปดูก่อน จ่ายเงินหน้างาน',
        description: 'ช่างไปดูอาการหน้างานและประเมินราคา',
        basePrice: baht(750),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'ไดชาร์จ (นอกสถานที่)',
        description: LABOR_ONLY,
        basePrice: baht(750),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ไดสตาร์ท (นอกสถานที่)',
        description: LABOR_ONLY,
        basePrice: baht(750),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ไล่เช็คระบบไฟ (นอกสถานที่)',
        description: LABOR_ONLY,
        basePrice: baht(750),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  {
    slug: 'battery',
    name: 'ช่างแบตเตอรี่รถยนต์',
    iconKey: 'battery',
    sortOrder: 3,
    subServices: [
      {
        name: 'จั๊มแบต (นอกสถานที่)',
        description: 'พ่วงแบตให้สตาร์ทติด',
        basePrice: baht(600),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนแบตเตอรี่ (นอกสถานที่)',
        description:
          'ค่าแรงติดตั้ง ไม่รวมราคาแบตเตอรี่ ช่างแจ้งราคาแบตตามรุ่นให้ยืนยันก่อน (มีแบตแล้วจ่ายเฉพาะค่าแรง)',
        basePrice: baht(600),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เรียกช่างไปวิเคราะห์อาการ',
        description: 'ช่างตรวจแบตเตอรี่และระบบไฟหน้างาน แล้วเสนอราคาให้ยืนยัน',
        basePrice: baht(550),
        priceType: PriceType.CALL_OUT_FEE,
      },
    ],
  },
  {
    slug: 'tire',
    name: 'ช่างปะยาง รถยนต์',
    iconKey: 'tire',
    sortOrder: 4,
    subServices: [
      {
        name: 'ปะยางตัวหนอน (นอกสถานที่)',
        description: 'ซ่อมรอยรั่วขนาดเล็กบริเวณหน้ายาง',
        basePrice: baht(790),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ปะยางสตีม (นอกสถานที่)',
        description: 'ซ่อมรอยรั่วแบบสตีม ช่างตรวจสภาพยางก่อนว่าซ่อมได้ปลอดภัย',
        basePrice: baht(990),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนยางอะไหล่ (นอกสถานที่)',
        description: 'เปลี่ยนเป็นยางอะไหล่ของลูกค้า ให้ขับไปร้านยางได้',
        basePrice: baht(790),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เรียกช่างให้ไปดูก่อน จ่ายเงินหน้างาน',
        description: 'ช่างตรวจยางและล้อหน้างานแล้วเสนอราคา',
        basePrice: baht(750),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'เปลี่ยนยาง (นอกสถานที่)',
        description: 'ค่าแรงถอดและติดตั้งยางใหม่ ไม่รวมค่ายาง',
        basePrice: baht(750),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  {
    slug: 'locksmith',
    name: 'ช่างกุญแจ รถยนต์',
    iconKey: 'key',
    sortOrder: 5,
    subServices: [
      {
        name: 'เรียกช่างให้ไปดูก่อน',
        description: 'ช่างไปดูอาการหน้างานและประเมินราคา',
        basePrice: baht(800),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'สะเดาะล็อค เปิดรถ (ลืมกุญแจไว้ในรถ)',
        description: 'เปิดรถจากภายนอก ไม่รวมทำกุญแจใหม่',
        basePrice: baht(1050),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ทำกุญแจ / โปรแกรม Smart Key (นอกสถานที่)',
        description:
          'ราคาเริ่มต้น ช่างแจ้งราคาจริงตามรุ่นรถ (ทำดอกใหม่ ลงชิป Immobilizer, Smart Key, รีโมท)',
        basePrice: baht(2100),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  {
    slug: 'towing',
    name: 'รถสไลด์/รถยก',
    iconKey: 'tow',
    sortOrder: 6,
    subServices: [
      {
        name: 'เรียกรถสไลด์ใกล้ฉัน',
        description:
          '1,500–5,000 บาท ตามระยะทาง เจ้าของรถสไลด์ประเมินราคาจริงให้ยืนยันก่อนยกรถ',
        infoNote: TOW_NOTE,
        basePrice: baht(1500),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'รถยก / รถติดหล่ม / กู้รถ',
        description: 'ราคาเริ่มต้น เจ้าของรถยกประเมินหน้างานก่อนเริ่มงาน',
        infoNote: TOW_NOTE,
        basePrice: baht(1500),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  {
    slug: 'fuel-delivery',
    name: 'น้ำมันหมด ส่งน้ำมันถึงที่',
    iconKey: 'fuel',
    sortOrder: 7,
    subServices: [
      {
        name: 'ส่งน้ำมันฉุกเฉิน',
        description: 'ค่าบริการส่งถึงที่ ไม่รวมค่าน้ำมัน (สูงสุด 10 ลิตร)',
        basePrice: baht(690),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  {
    slug: 'ev-assist',
    name: 'ช่างรถ EV',
    iconKey: 'ev',
    sortOrder: 8,
    subServices: [
      {
        name: 'ล้างแผงแอร์ คอยล์ร้อน รถ EV',
        description:
          'ล้างแผงคอยล์ร้อนแอร์ถึงที่ ช่วยให้แอร์เย็นและระบายความร้อนแบตได้ดีขึ้น',
        basePrice: baht(1890),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ตรวจเช็กอาการรถ EV (นอกสถานที่)',
        description: LABOR_ONLY,
        basePrice: baht(1300),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ตรวจอาการชาร์จไม่เข้าเบื้องต้น (นอกสถานที่)',
        description: LABOR_ONLY,
        basePrice: baht(1300),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'อ่านโค้ด ไฟเตือนระบบ EV (นอกสถานที่)',
        description: LABOR_ONLY,
        basePrice: baht(1300),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เรียกช่างให้ไปดูก่อน',
        description: 'ช่างไปดูอาการหน้างานและประเมินราคา',
        basePrice: baht(750),
        priceType: PriceType.CALL_OUT_FEE,
      },
    ],
  },
  {
    slug: 'used-car-inspection',
    name: 'ตรวจรถมือสองนอกสถานที่',
    iconKey: 'inspection',
    sortOrder: 9,
    subServices: [
      {
        name: 'ตรวจรถมือสองนอกสถานที่',
        description:
          'ตรวจ 134 จุดถึงที่ เช็กรถจมน้ำ ชนหนัก กรอไมล์ วัดความหนาสี สแกน OBD2 พร้อมรายงานในแอป ราคาเดียวทุกประเภทรถ',
        infoNote:
          'ช่างตรวจเอกสาร โครงสร้างตัวถัง สีทุกชิ้น ร่องรอยน้ำท่วม ห้องเครื่อง คอมพิวเตอร์รถ ช่วงล่าง ยาง ระบบไฟฟ้า และทดลองขับ ใช้เวลาประมาณ 60–90 นาที ผลเป็นเกรด A–E พร้อมคำแนะนำว่าควรซื้อหรือไม่',
        basePrice: baht(1990),
        fixedPrice: true,
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
];

async function main(): Promise<void> {
  for (const vehicleType of VEHICLE_TYPES) {
    await prisma.vehicleType.upsert({
      where: { slug: vehicleType.slug },
      create: vehicleType,
      update: vehicleType,
    });
  }

  for (const category of CATEGORIES) {
    const { subServices, ...categoryData } = category;

    const saved = await prisma.serviceCategory.upsert({
      where: { slug: categoryData.slug },
      create: categoryData,
      update: categoryData,
    });

    // upsert ทีละรายการแทนการลบทั้งหมดแล้วสร้างใหม่ — ลบทิ้งไม่ได้ถ้ามีออเดอร์
    // อ้างอิง subService นั้นอยู่แล้ว (ติด foreign key) จับคู่ด้วยชื่อภายในหมวดเดียวกัน
    for (const [index, subService] of subServices.entries()) {
      const existing = await prisma.subService.findFirst({
        where: { categoryId: saved.id, name: subService.name },
      });

      if (existing) {
        await prisma.subService.update({
          where: { id: existing.id },
          // ค่าที่ไม่ได้ระบุต้องรีเซ็ต ไม่อย่างนั้นค่าเดิม (เช่น fixedPrice ของมัดจำรถสไลด์) จะค้างอยู่
          data: {
            fixedPrice: false,
            infoNote: null,
            ...subService,
            sortOrder: index + 1,
            active: true,
          },
        });
      } else {
        await prisma.subService.create({
          data: { ...subService, categoryId: saved.id, sortOrder: index + 1 },
        });
      }
    }

    // บริการย่อยที่เลิกขายแล้วลบไม่ได้ถ้ามีออเดอร์อ้างอิง จึงปิดการแสดงแทน
    await prisma.subService.updateMany({
      where: {
        categoryId: saved.id,
        name: { notIn: subServices.map((subService) => subService.name) },
      },
      data: { active: false },
    });
  }

  console.log('seed เสร็จเรียบร้อย');
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(() => void prisma.$disconnect());
