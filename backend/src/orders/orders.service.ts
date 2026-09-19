import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrderStatus, PaymentStatus } from '@prisma/client';
import { randomInt } from 'node:crypto';

import { PrismaService } from '../prisma/prisma.service';
import { CatalogService } from '../catalog/catalog.service';
import { DispatchService } from '../dispatch/dispatch.service';
import { DEFAULT_COMMISSION_RATE } from '../common/constants';
import { CompleteOrderDto, CreateOrderDto, RateOrderDto } from './dto/order.dto';

/** สถานะที่ช่างเปลี่ยนเองได้ และสถานะก่อนหน้าที่อนุญาต */
const PROVIDER_TRANSITIONS: Partial<Record<OrderStatus, OrderStatus>> = {
  [OrderStatus.EN_ROUTE]: OrderStatus.MATCHED,
  [OrderStatus.IN_PROGRESS]: OrderStatus.EN_ROUTE,
};

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: CatalogService,
    private readonly dispatch: DispatchService,
  ) {}

  private generateOrderNo(): string {
    const now = new Date();
    const datePart = now.toISOString().slice(2, 10).replace(/-/g, '');
    const randomPart = randomInt(0, 10_000).toString().padStart(4, '0');
    return `FG${datePart}${randomPart}`;
  }

  async create(customerId: string, dto: CreateOrderDto) {
    const quote = await this.catalog.quote(dto.subServiceId, dto.vehicleTypeId);

    const order = await this.prisma.order.create({
      data: {
        orderNo: this.generateOrderNo(),
        customerId,
        categoryId: dto.categoryId,
        subServiceId: dto.subServiceId,
        vehicleTypeId: dto.vehicleTypeId,
        pickupLat: dto.pickupLat,
        pickupLng: dto.pickupLng,
        pickupAddress: dto.pickupAddress,
        note: dto.note,
        priceEstimated: quote.price,
        commissionRate: DEFAULT_COMMISSION_RATE,
        status: OrderStatus.CREATED,
        photos: dto.photoUrls?.length
          ? { create: dto.photoUrls.map((url) => ({ url })) }
          : undefined,
      },
    });

    await this.dispatch.startDispatch(order.id);

    return this.findById(order.id);
  }

  async findById(orderId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: {
        category: true,
        subService: true,
        vehicleType: true,
        photos: true,
        payment: true,
        rating: true,
        provider: {
          select: {
            id: true,
            realName: true,
            nickname: true,
            phone: true,
            ratingAvg: true,
            currentLat: true,
            currentLng: true,
          },
        },
      },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    return order;
  }

  listForCustomer(customerId: string) {
    return this.prisma.order.findMany({
      where: { customerId },
      include: { category: true, subService: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  listForProvider(providerId: string) {
    return this.prisma.order.findMany({
      where: { providerId },
      include: { category: true, subService: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async cancelByCustomer(customerId: string, orderId: string) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.customerId !== customerId) {
      throw new ForbiddenException('ยกเลิกออเดอร์ของคนอื่นไม่ได้');
    }
    // ยกเลิกได้เฉพาะก่อนช่างเริ่มทำงานจริง
    if (
      order.status !== OrderStatus.CREATED &&
      order.status !== OrderStatus.SEARCHING &&
      order.status !== OrderStatus.MATCHED
    ) {
      throw new BadRequestException('ออเดอร์นี้ยกเลิกไม่ได้แล้ว');
    }

    return this.prisma.order.update({
      where: { id: orderId },
      data: { status: OrderStatus.CANCELLED, cancelledAt: new Date() },
    });
  }

  async updateStatusByProvider(
    providerId: string,
    orderId: string,
    next: OrderStatus,
  ) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.providerId !== providerId) {
      throw new ForbiddenException('ออเดอร์นี้ไม่ใช่ของคุณ');
    }

    const requiredPrevious = PROVIDER_TRANSITIONS[next];
    if (!requiredPrevious || order.status !== requiredPrevious) {
      throw new BadRequestException('เปลี่ยนสถานะจากขั้นตอนปัจจุบันไม่ได้');
    }

    return this.prisma.order.update({
      where: { id: orderId },
      data: { status: next },
    });
  }

  /** ช่างปิดงานพร้อมกรอกราคาสุดท้าย ระบบสร้างรายการชำระเงินรอลูกค้าจ่าย */
  async completeByProvider(
    providerId: string,
    orderId: string,
    dto: CompleteOrderDto,
  ) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.providerId !== providerId) {
      throw new ForbiddenException('ออเดอร์นี้ไม่ใช่ของคุณ');
    }
    if (order.status !== OrderStatus.IN_PROGRESS) {
      throw new BadRequestException('ต้องอยู่ในสถานะกำลังดำเนินการก่อนปิดงาน');
    }

    await this.prisma.$transaction([
      this.prisma.order.update({
        where: { id: orderId },
        data: {
          status: OrderStatus.COMPLETED,
          priceFinal: dto.priceFinal,
          completedAt: new Date(),
        },
      }),
      this.prisma.payment.create({
        data: {
          orderId,
          amount: dto.priceFinal,
          status: PaymentStatus.PENDING,
        },
      }),
    ]);

    return this.findById(orderId);
  }

  async rate(customerId: string, orderId: string, dto: RateOrderDto) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { rating: true },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.customerId !== customerId) {
      throw new ForbiddenException('ให้คะแนนออเดอร์ของคนอื่นไม่ได้');
    }
    if (order.status !== OrderStatus.COMPLETED) {
      throw new BadRequestException('ให้คะแนนได้เฉพาะงานที่เสร็จแล้ว');
    }
    if (order.rating) {
      throw new BadRequestException('ออเดอร์นี้ให้คะแนนไปแล้ว');
    }
    if (!order.providerId) {
      throw new BadRequestException('ออเดอร์นี้ไม่มีช่างรับผิดชอบ');
    }

    const providerId = order.providerId;

    return this.prisma.$transaction(async (tx) => {
      const rating = await tx.rating.create({
        data: { orderId, score: dto.score, comment: dto.comment },
      });

      const provider = await tx.provider.findUniqueOrThrow({
        where: { id: providerId },
        select: { ratingAvg: true, ratingCount: true },
      });

      const nextCount = provider.ratingCount + 1;
      const nextAvg =
        (provider.ratingAvg * provider.ratingCount + dto.score) / nextCount;

      await tx.provider.update({
        where: { id: providerId },
        data: { ratingAvg: nextAvg, ratingCount: nextCount },
      });

      return rating;
    });
  }
}
