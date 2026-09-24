import 'dotenv/config';
import { PrismaClient, ProviderStatus } from '@prisma/client';

/**
 * เตรียมบัญชีช่างที่อนุมัติแล้วให้ทีมรีวิวของ Apple/Google ล็อกอินเข้าแอป FixGo Fixer ได้
 *
 * ใช้: REVIEW_PROVIDER_PHONE=0800000002 npm run seed:review
 * เบอร์นี้ต้องอยู่ใน REVIEW_LOGIN_PHONES ด้วย (ดู docs/APP_REVIEW.md)
 */
const prisma = new PrismaClient();

async function main() {
  const phone = process.env.REVIEW_PROVIDER_PHONE?.trim();
  if (!phone || !/^0\d{8,9}$/.test(phone)) {
    throw new Error('ตั้ง REVIEW_PROVIDER_PHONE เป็นเบอร์ไทย 9-10 หลักก่อน');
  }
  const allowed = (process.env.REVIEW_LOGIN_PHONES ?? '')
    .split(',')
    .map((value) => value.trim());
  if (!allowed.includes(phone)) {
    console.warn(
      'คำเตือน: เบอร์นี้ยังไม่อยู่ใน REVIEW_LOGIN_PHONES ทีมรีวิวจะรับ OTP ไม่ได้',
    );
  }

  const [categories, vehicleTypes] = await Promise.all([
    prisma.serviceCategory.findMany({ select: { id: true } }),
    prisma.vehicleType.findMany({ select: { id: true } }),
  ]);

  const data = {
    realName: 'บัญชีทดสอบ App Review',
    nickname: 'รีวิว',
    experienceYears: 5,
    baseLat: 13.7563,
    baseLng: 100.5018,
    openMinute: 0,
    closeMinute: 1439,
    status: ProviderStatus.VERIFIED,
  };
  const provider = await prisma.provider.upsert({
    where: { phone },
    create: { phone, ...data },
    update: data,
  });
  await prisma.providerServiceCategory.deleteMany({
    where: { providerId: provider.id },
  });
  await prisma.providerVehicleType.deleteMany({
    where: { providerId: provider.id },
  });
  await prisma.providerServiceCategory.createMany({
    data: categories.map((c) => ({
      providerId: provider.id,
      categoryId: c.id,
    })),
  });
  await prisma.providerVehicleType.createMany({
    data: vehicleTypes.map((v) => ({
      providerId: provider.id,
      vehicleTypeId: v.id,
    })),
  });
  console.log(`พร้อมแล้ว: ช่างทดสอบ ${phone} (${provider.id}) สถานะ VERIFIED`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
