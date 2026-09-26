import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

import { hashPassword } from '../src/admin/admin.service';

/**
 * สร้างบัญชีผู้ดูแลระบบคนแรก
 * ใช้: npx ts-node prisma/create-admin.ts 0812345678 "ชื่อแอดมิน" รหัสผ่าน
 */
const prisma = new PrismaClient();

async function main(): Promise<void> {
  const [phone, name, password] = process.argv.slice(2);

  if (!phone || !name || !password) {
    console.error(
      'ใช้: npx ts-node prisma/create-admin.ts <เบอร์โทร> <ชื่อ> <รหัสผ่าน>',
    );
    process.exit(1);
  }

  const admin = await prisma.adminUser.upsert({
    where: { phone },
    create: { phone, name, passwordHash: hashPassword(password) },
    update: { name, passwordHash: hashPassword(password) },
  });

  console.log(`สร้าง/อัปเดตบัญชีแอดมินแล้ว: ${admin.phone}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(() => void prisma.$disconnect());
