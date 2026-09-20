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
  {
    slug: 'battery',
    name: 'ช่างแบตเตอรี่รถยนต์',
    iconKey: 'battery',
    sortOrder: 3,
    subServices: [
      {
        name: 'พ่วงแบตเตอรี่ (จั๊มแบต)',
        description: 'บริการพ่วงแบตนอกสถานที่',
        basePrice: baht(499),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนแบตเตอรี่นอกสถานที่',
        description: 'ค่าบริการเริ่มต้น ไม่รวมค่าแบตเตอรี่',
        basePrice: baht(749),
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
        name: 'ปะยางนอกสถานที่',
        description: 'ค่าบริการเริ่มต้นต่อเส้น',
        basePrice: baht(499),
        priceType: PriceType.FULL_SERVICE,
      },
      {
        name: 'เปลี่ยนยางอะไหล่',
        description: 'ค่าบริการเปลี่ยนยางอะไหล่หน้างาน',
        basePrice: baht(499),
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
        name: 'เปิดรถกรณีกุญแจค้างในรถ',
        description: 'ค่าบริการเริ่มต้น',
        basePrice: baht(1177),
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
  {
    slug: 'used-car-inspection',
    name: 'ตรวจรถมือสองนอกสถานที่',
    iconKey: 'inspection',
    sortOrder: 7,
    subServices: [
      {
        name: 'ตรวจรถมือสองนอกสถานที่',
        description: 'ตรวจสภาพก่อนซื้อถึงสถานที่ พร้อมรายงานอิเล็กทรอนิกส์ ราคาเดียวทุกประเภทรถ',
        basePrice: baht(1490),
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
          data: { ...subService, sortOrder: index + 1 },
        });
      } else {
        await prisma.subService.create({
          data: { ...subService, categoryId: saved.id, sortOrder: index + 1 },
        });
      }
    }
  }

  console.log('seed เสร็จเรียบร้อย');
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(() => void prisma.$disconnect());
