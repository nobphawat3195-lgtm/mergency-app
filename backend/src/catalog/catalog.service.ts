import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class CatalogService {
  constructor(private readonly prisma: PrismaService) {}

  /** หมวดบริการทั้งหมด (Step 1 ของ booking wizard) */
  listCategories() {
    return this.prisma.serviceCategory.findMany({
      where: { active: true },
      orderBy: { sortOrder: 'asc' },
    });
  }

  /** บริการย่อยในหมวด (Step 2) */
  async listSubServices(categoryId: string) {
    const category = await this.prisma.serviceCategory.findUnique({
      where: { id: categoryId },
    });
    if (!category || !category.active)
      throw new NotFoundException('ไม่พบหมวดบริการนี้');

    return this.prisma.subService.findMany({
      where: { categoryId, active: true },
      orderBy: { sortOrder: 'asc' },
    });
  }

  /** ประเภทรถ (Step 3) */
  listVehicleTypes() {
    return this.prisma.vehicleType.findMany({
      where: { active: true },
      orderBy: { sortOrder: 'asc' },
    });
  }

  /** ราคาสุดท้าย = ราคาตั้งต้นของบริการย่อย x ตัวคูณประเภทรถ */
  async quote(
    subServiceId: string,
    vehicleTypeId: string,
    db: Prisma.TransactionClient = this.prisma,
  ): Promise<{ price: number; subServiceId: string; vehicleTypeId: string }> {
    const [subService, vehicleType] = await Promise.all([
      db.subService.findUnique({
        where: { id: subServiceId },
        include: { category: { select: { active: true } } },
      }),
      db.vehicleType.findUnique({ where: { id: vehicleTypeId } }),
    ]);

    if (!subService) throw new NotFoundException('ไม่พบบริการย่อยนี้');
    // แอดมินปิดหมวด/บริการไว้ (เช่น ยังไม่มีช่างรับ) ลูกค้าที่เปิดแอปค้างไว้ก็สั่งไม่ได้
    if (!subService.active || !subService.category.active)
      throw new BadRequestException(
        'บริการนี้ปิดรับงานชั่วคราว กรุณาเลือกบริการอื่น',
      );
    if (!vehicleType || !vehicleType.active)
      throw new NotFoundException('ไม่พบประเภทรถนี้');

    return {
      price: subService.fixedPrice
        ? subService.basePrice
        : Math.round(subService.basePrice * vehicleType.multiplier),
      subServiceId,
      vehicleTypeId,
    };
  }
}
