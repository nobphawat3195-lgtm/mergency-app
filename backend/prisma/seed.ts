import 'dotenv/config';
import { PrismaClient, PriceType } from '@prisma/client';

const prisma = new PrismaClient();

/** ราคาเก็บเป็นสตางค์ */
const baht = (amount: number): number => amount * 100;

const VEHICLE_TYPES = [
  { slug: 'sedan', name: 'รถเก๋ง', multiplier: 1.0, sortOrder: 1 },
  { slug: 'suv', name: 'รถ SUV', multiplier: 1.15, sortOrder: 2 },
  { slug: 'pickup', name: 'รถกระบะ', multiplier: 1.15, sortOrder: 3 },
  { slug: 'van', name: 'รถตู้', multiplier: 1.2, sortOrder: 4 },
  { slug: 'motorcycle', name: 'มอเตอร์ไซค์', multiplier: 0.7, sortOrder: 5 },
  { slug: 'ev', name: 'รถ EV', multiplier: 1.25, sortOrder: 6 },
  { slug: 'euro', name: 'รถยุโรป', multiplier: 1.4, sortOrder: 7 },
  { slug: 'truck', name: 'รถบรรทุก', multiplier: 1.5, sortOrder: 8 },
  { slug: 'machinery', name: 'เครื่องจักร', multiplier: 1.5, sortOrder: 9 },
];

const CATEGORIES = [
  {
    slug: 'car-mechanic',
    name: 'ช่างซ่อมรถยนต์',
    iconKey: 'mechanic',
    sortOrder: 1,
    subServices: [
      {
        name: 'เรียกช่างให้ไปดูก่อน จ่ายเงินหน้างาน',
        description: 'ค่าเดินทาง เรียกไปดูอาการเสนอราคาเพิ่มเติมหากมีการซ่อม',
        basePrice: baht(749),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'ซ่อมนอกสถานที่',
        description: 'ซ่อมพื้นฐาน ไม่รวมค่าอะไหล่และค่าบริการซ่อม',
        basePrice: baht(856),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ตรวจสอบเบื้องต้น (นอกสถานที่)',
        description: 'เช็คอาการเบื้องต้นเพื่อเสนอราคาซ่อม',
        basePrice: baht(749),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'รถมีไฟเตือนขึ้นหน้าปัด',
        description: 'รูปไฟโชว์เรียกช่างไปตรวจสอบหน้างาน',
        basePrice: baht(749),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'รถสตาร์ทไม่ติด',
        description: 'เรียกไปดูอาการหน้างานและประเมินเบื้องต้น',
        basePrice: baht(749),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'ดับกลางทาง',
        description: 'เรียกไปดูอาการหน้างานและประเมินเบื้องต้น',
        basePrice: baht(749),
        priceType: PriceType.CALL_OUT_FEE,
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
        description: 'เรียกไปดูอาการหน้างานและประเมิน',
        basePrice: baht(400),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'ไดชาร์จ (นอกสถานที่)',
        description: 'เริ่มต้น',
        basePrice: baht(1177),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ไดสตาร์ท (นอกสถานที่)',
        description: 'เริ่มต้น',
        basePrice: baht(1177),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ไล่เช็คระบบไฟ (นอกสถานที่)',
        description: 'เริ่มต้น',
        basePrice: baht(1177),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  // ราคาหมวดแบต ยาง กุญแจ อิงตามแอป 24CarFix (ภาพหน้าจอจากเจ้าของโปรเจกต์ ก.ย. 2569)
  {
    slug: 'battery',
    name: 'ช่างแบตเตอรี่รถยนต์',
    iconKey: 'battery',
    sortOrder: 3,
    subServices: [
      {
        name: 'เรียกช่างให้ไปดูก่อน จ่ายเงินหน้างาน',
        description: 'ช่างไปดูอาการและประเมินราคาซ่อมหน้างาน',
        basePrice: baht(535),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'จั๊มแบต (นอกสถานที่)',
        description: 'พ่วงแบตให้สตาร์ทติด ค่าบริการเบื้องต้น',
        basePrice: baht(535),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนแบต (ช่างนำแบตไปติดตั้ง)',
        description: 'ค่าบริการเริ่มต้น ไม่รวมค่าแบต ช่างแจ้งราคาแบตตามรุ่นให้ยืนยันก่อน',
        basePrice: baht(428),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนแบต (ลูกค้ามีแบตแล้ว)',
        description: 'จ่ายเฉพาะค่าแรงติดตั้ง',
        basePrice: baht(442),
        priceType: PriceType.FULL_SERVICE,
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
        name: 'เรียกช่างให้ไปดูก่อน จ่ายเงินหน้างาน',
        description: 'ช่างตรวจยางและล้อหน้างานแล้วเสนอราคา',
        basePrice: baht(856),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'ปะยางตัวหนอน (นอกสถานที่)',
        description: 'ซ่อมรอยรั่วขนาดเล็กบริเวณหน้ายาง',
        basePrice: baht(856),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนยาง (นอกสถานที่)',
        description: 'ถอดยางเดิมและติดตั้งยางใหม่ ไม่รวมค่ายาง',
        basePrice: baht(856),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ปะยางสตรีมเย็น (นอกสถานที่)',
        description: 'ซ่อมรอยรั่วหน้ายางแบบสตรีมเย็น',
        basePrice: baht(1070),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ปะยางสตรีมร้อน (นอกสถานที่)',
        description: 'ซ่อมรอยรั่วแบบสตรีมร้อน ช่างตรวจสภาพยางก่อนว่าซ่อมได้ปลอดภัย',
        basePrice: baht(1391),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนยางอะไหล่ (นอกสถานที่)',
        description: 'เปลี่ยนเป็นยางอะไหล่ของลูกค้า ให้ขับไปร้านยางได้',
        basePrice: baht(749),
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
        basePrice: baht(856),
        priceType: PriceType.CALL_OUT_FEE,
      },
      {
        name: 'สะเดาะล็อครถ (เปิดรถจากภายนอก)',
        description: 'เปิดรถจากภายนอก ไม่รวมทำกุญแจใหม่',
        basePrice: baht(1070),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปิดรถยนต์ฉุกเฉิน (นอกสถานที่)',
        description: 'ลืมกุญแจไว้ในรถ กุญแจหาย หรือระบบล็อกขัดข้อง',
        basePrice: baht(1070),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ทำกุญแจรถยนต์ (นอกสถานที่)',
        description: 'ทำกุญแจใหม่ที่จุดจอดรถ กรณีกุญแจหาย ชำรุด หรือทำดอกสำรอง',
        basePrice: baht(1926),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'โปรแกรมกุญแจ Immobilizer (นอกสถานที่)',
        description: 'ลงทะเบียนชิปกุญแจเข้ากับระบบกันขโมยของรถ',
        basePrice: baht(2996),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'โปรแกรม Smart Key (นอกสถานที่)',
        description: 'ลงทะเบียน Smart Key เข้ากับระบบ Keyless และระบบสตาร์ท',
        basePrice: baht(4173),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'โปรแกรมรีโมทรถยนต์ (นอกสถานที่)',
        description: 'ลงทะเบียนรีโมทเข้ากับระบบล็อก/ปลดล็อก',
        basePrice: baht(2461),
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
        name: 'รถสไลด์ในเขตเมือง',
        description: 'ค่าบริการเริ่มต้น ระยะทางเพิ่มคิดตามจริง',
        basePrice: baht(1500),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  // ราคา 2 หมวดนี้เป็นราคาชั่วคราวตามตลาด รอเทียบกับ 24CarFix แล้วปรับในหลังบ้าน
  {
    slug: 'fuel-delivery',
    name: 'น้ำมันหมด ส่งน้ำมันถึงที่',
    iconKey: 'fuel',
    sortOrder: 7,
    subServices: [
      {
        name: 'ส่งน้ำมันฉุกเฉิน',
        description: 'ค่าบริการส่งถึงที่ ไม่รวมค่าน้ำมัน (สูงสุด 10 ลิตร)',
        basePrice: baht(590),
        priceType: PriceType.FULL_SERVICE,
      },
    ],
  },
  {
    slug: 'ev-assist',
    name: 'รถ EV แบตหมด',
    iconKey: 'ev',
    sortOrder: 8,
    subServices: [
      {
        name: 'ชาร์จไฟฉุกเฉินนอกสถานที่',
        description: 'ชาร์จพอให้ขับไปสถานีชาร์จใกล้สุดได้ (ประมาณ 20–30 กม.)',
        basePrice: baht(1290),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'ยกรถ EV ด้วยรถสไลด์พื้นเรียบ',
        description: 'รถ EV ห้ามลากล้อแตะพื้น ค่าบริการเริ่มต้น ระยะทางเพิ่มคิดตามจริง',
        basePrice: baht(1800),
        priceType: PriceType.FULL_SERVICE,
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
          data: { ...subService, sortOrder: index + 1, active: true },
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
