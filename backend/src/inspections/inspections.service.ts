import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrderStatus, Prisma, Role } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { CHECKLIST, CHECKLIST_VERSION, findChecklistItem } from './checklist';
import {
  gradeInspection,
  missingItems,
  resolveStatus,
  VehicleProfile,
} from './grading';
import {
  InspectionBookingDto,
  UpdateInspectionDto,
} from './dto/inspection.dto';

/** slug หมวดบริการที่ต้องมีรายงานตรวจรถ ตรงกับ prisma/seed.ts */
export const INSPECTION_CATEGORY_SLUG = 'used-car-inspection';

/** ช่างบันทึกรายงานได้ตั้งแต่ออกเดินทางจนก่อนปิดงาน */
const EDITABLE_STATUSES: OrderStatus[] = [
  OrderStatus.EN_ROUTE,
  OrderStatus.IN_PROGRESS,
];

type Actor = { sub: string; role: Role };

@Injectable()
export class InspectionsService {
  constructor(private readonly prisma: PrismaService) {}

  checklist() {
    return { version: CHECKLIST_VERSION, sections: CHECKLIST };
  }

  /** สร้างรายงานเปล่าพร้อมข้อมูลนัดหมาย เรียกตอนลูกค้าสร้างออเดอร์ตรวจรถ */
  createForOrder(
    tx: Prisma.TransactionClient,
    orderId: string,
    booking: InspectionBookingDto | undefined,
  ) {
    return tx.inspectionReport.create({
      data: {
        orderId,
        checklistVersion: CHECKLIST_VERSION,
        brand: booking?.brand,
        model: booking?.model,
        year: booking?.year,
        listingUrl: booking?.listingUrl,
        sellerName: booking?.sellerName,
        sellerPhone: booking?.sellerPhone,
        appointmentAt: booking?.appointmentAt
          ? new Date(booking.appointmentAt)
          : undefined,
      },
    });
  }

  private async loadOrder(orderId: string, actor: Actor) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: {
        id: true,
        status: true,
        customerId: true,
        providerId: true,
        category: { select: { slug: true } },
      },
    });
    const isParty =
      order &&
      ((actor.role === Role.CUSTOMER && order.customerId === actor.sub) ||
        (actor.role === Role.PROVIDER && order.providerId === actor.sub));
    if (!order || !isParty) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.category.slug !== INSPECTION_CATEGORY_SLUG) {
      throw new BadRequestException('ออเดอร์นี้ไม่ใช่งานตรวจรถมือสอง');
    }
    return order;
  }

  private async loadReport(orderId: string) {
    const report = await this.prisma.inspectionReport.findUnique({
      where: { orderId },
      include: { items: { orderBy: { itemCode: 'asc' } } },
    });
    if (!report)
      throw new NotFoundException('ยังไม่มีรายงานตรวจรถของออเดอร์นี้');
    return report;
  }

  /**
   * ลูกค้าเห็นผลตรวจรายข้อเฉพาะหลังช่างส่งรายงานแล้ว ระหว่างตรวจเห็นแค่ข้อมูลนัดหมาย
   * กันลูกค้าตัดสินใจจากผลที่ยังตรวจไม่ครบ
   */
  async getForActor(orderId: string, actor: Actor) {
    await this.loadOrder(orderId, actor);
    const report = await this.loadReport(orderId);
    if (actor.role === Role.CUSTOMER && !report.submittedAt) {
      return { ...report, items: [] };
    }
    return report;
  }

  async update(orderId: string, providerId: string, dto: UpdateInspectionDto) {
    const order = await this.loadOrder(orderId, {
      sub: providerId,
      role: Role.PROVIDER,
    });
    if (!EDITABLE_STATUSES.includes(order.status)) {
      throw new BadRequestException(
        'แก้ไขรายงานได้ระหว่างเดินทางและระหว่างตรวจเท่านั้น',
      );
    }
    const report = await this.loadReport(orderId);
    if (report.submittedAt) {
      throw new BadRequestException('ส่งรายงานไปแล้ว แก้ไขไม่ได้');
    }

    for (const item of dto.items ?? []) {
      if (!findChecklistItem(item.itemCode)) {
        throw new BadRequestException(`ไม่รู้จักรายการตรวจ ${item.itemCode}`);
      }
    }

    const { items, ...vehicle } = dto;
    await this.prisma.$transaction(async (tx) => {
      await tx.inspectionReport.update({
        where: { id: report.id },
        data: vehicle,
      });
      for (const item of items ?? []) {
        const data = {
          status: item.status ?? null,
          measurement: item.measurement ?? null,
          note: item.note ?? null,
          photoUrls: item.photoUrls ?? [],
        };
        await tx.inspectionItemResult.upsert({
          where: {
            reportId_itemCode: { reportId: report.id, itemCode: item.itemCode },
          },
          create: { reportId: report.id, itemCode: item.itemCode, ...data },
          update: data,
        });
      }
    });

    return this.loadReport(orderId);
  }

  async submit(orderId: string, providerId: string) {
    const order = await this.loadOrder(orderId, {
      sub: providerId,
      role: Role.PROVIDER,
    });
    if (order.status !== OrderStatus.IN_PROGRESS) {
      throw new BadRequestException('ส่งรายงานได้เมื่อเริ่มตรวจแล้วเท่านั้น');
    }
    const report = await this.loadReport(orderId);
    if (report.submittedAt) {
      throw new BadRequestException('ส่งรายงานไปแล้ว');
    }

    const requiredVehicleFields: [string, unknown][] = [
      ['ยี่ห้อ', report.brand],
      ['รุ่น', report.model],
      ['ปีรถ', report.year],
      ['ทะเบียน', report.plateNo],
      ['เลขตัวถัง', report.vin],
      ['เลขไมล์', report.mileageKm],
      ['ระบบขับเคลื่อน', report.powertrain],
      ['ระบบเกียร์', report.transmission],
    ];
    const missingVehicle = requiredVehicleFields
      .filter(
        ([, value]) => value === null || value === undefined || value === '',
      )
      .map(([label]) => label);
    if (missingVehicle.length > 0) {
      throw new BadRequestException(
        `กรอกข้อมูลรถให้ครบก่อนส่ง: ${missingVehicle.join(', ')}`,
      );
    }

    const vehicle: VehicleProfile = {
      powertrain: report.powertrain as VehicleProfile['powertrain'],
      transmission: report.transmission as VehicleProfile['transmission'],
    };
    const results = report.items.map((item) => ({
      itemCode: item.itemCode,
      status: item.status,
      measurement: item.measurement,
    }));

    const missing = missingItems(results, vehicle);
    if (missing.length > 0) {
      throw new BadRequestException(
        `ยังตรวจไม่ครบ ${missing.length} รายการ: ${missing.slice(0, 10).join(', ')}${missing.length > 10 ? ' ...' : ''}`,
      );
    }

    // ใช้ผลที่คำนวณจากค่าวัดด้วย เช่น สีหนา 240 ไมครอน = ควรระวัง ต้องมีรูปเหมือนกัน
    const missingPhotos = report.items
      .filter((item) => {
        const definition = findChecklistItem(item.itemCode);
        if (!definition?.photoOnIssue) return false;
        const status = resolveStatus(definition, item);
        return (
          (status === 'FAIL' || status === 'ATTENTION') &&
          item.photoUrls.length === 0
        );
      })
      .map((item) => item.itemCode);
    if (missingPhotos.length > 0) {
      throw new BadRequestException(
        `ต้องแนบรูปข้อที่ไม่ผ่าน/ควรระวัง: ${missingPhotos.join(', ')}`,
      );
    }

    const result = gradeInspection(results, vehicle);
    await this.prisma.inspectionReport.update({
      where: { id: report.id },
      data: {
        score: result.score,
        grade: result.grade,
        verdict: result.verdict,
        floodSuspected: result.floodSuspected,
        accidentSuspected: result.accidentSuspected,
        odometerSuspected: result.odometerSuspected,
        legalIssue: result.legalIssue,
        submittedAt: new Date(),
      },
    });

    return { ...(await this.loadReport(orderId)), sections: result.sections };
  }

  /** ใช้ตอนปิดงาน: งานตรวจรถต้องส่งรายงานก่อนเสมอ */
  async assertSubmittedIfRequired(orderId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: {
        category: { select: { slug: true } },
        inspection: { select: { submittedAt: true } },
      },
    });
    if (
      order?.category.slug === INSPECTION_CATEGORY_SLUG &&
      !order.inspection?.submittedAt
    ) {
      throw new BadRequestException('ต้องส่งรายงานตรวจรถก่อนปิดงาน');
    }
  }
}
