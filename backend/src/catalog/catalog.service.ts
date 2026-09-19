import { Injectable, NotFoundException } from '@nestjs/common';

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
    if (!category) throw new NotFoundException('ไม่พบหมวดบริการนี้');

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
  ): Promise<{ price: number; subServiceId: string; vehicleTypeId: string }> {
    const [subService, vehicleType] = await Promise.all([
      this.prisma.subService.findUnique({ where: { id: subServiceId } }),
      this.prisma.vehicleType.findUnique({ where: { id: vehicleTypeId } }),
    ]);

    if (!subService) throw new NotFoundException('ไม่พบบริการย่อยนี้');
    if (!vehicleType) throw new NotFoundException('ไม่พบประเภทรถนี้');

    return {
      price: Math.round(subService.basePrice * vehicleType.multiplier),
      subServiceId,
      vehicleTypeId,
    };
  }
}
