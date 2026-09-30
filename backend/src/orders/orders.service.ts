import {
  BadRequestException,
  ForbiddenException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  OrderStatus,
  PaymentStatus,
  QuoteStatus,
  Role,
  DispatchStatus,
  Prisma,
} from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { CatalogService } from '../catalog/catalog.service';
import { DispatchService } from '../dispatch/dispatch.service';
import { PushService } from '../notifications/push.service';
import { UploadsService } from '../uploads/uploads.service';
import { serializable } from '../common/transaction';
import { commissionRate } from '../common/constants';
import {
  INSPECTION_CATEGORY_SLUG,
  InspectionsService,
} from '../inspections/inspections.service';
import { PROVIDER_CARD_SELECT, presentProviderCard } from './provider-card';
import {
  CreateOrderDto,
  ProposeQuoteDto,
  RateOrderDto,
  RespondQuoteDto,
} from './dto/order.dto';

/** ไม่ส่งรูปสลิปออกไปกับข้อมูลงาน (ช่างไม่ควรเห็นบัญชีธนาคารของลูกค้า) แอดมินดูได้ในหน้าตรวจสลิป */
const PAYMENT_SUMMARY = {
  select: {
    id: true,
    amount: true,
    method: true,
    status: true,
    paidAt: true,
    slipSubmittedAt: true,
    slipRejectReason: true,
  },
} as const;

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
    private readonly inspections: InspectionsService,
    private readonly push: PushService,
    private readonly uploads: UploadsService,
  ) {}

  private async generateOrderNo(tx: Prisma.TransactionClient): Promise<string> {
    const [row] = await tx.$queryRaw<
      { value: bigint }[]
    >`SELECT nextval('fixgo_order_no_seq') AS value`;
    const datePart = new Date(Date.now() + 7 * 3600000)
      .toISOString()
      .slice(2, 10)
      .replace(/-/g, '');
    return `FG${datePart}-${row.value.toString().padStart(8, '0')}`;
  }

  async create(customerId: string, dto: CreateOrderDto) {
    this.uploads.assertOwnedUploads(dto.photoUrls, customerId, 'ORDER');
    const order = await serializable(this.prisma, async (tx) => {
      const quote = await this.catalog.quote(
        dto.subServiceId,
        dto.vehicleTypeId,
        tx,
      );
      const subService = await tx.subService.findUniqueOrThrow({
        where: { id: dto.subServiceId },
        include: { category: { select: { slug: true } } },
      });
      if (subService.categoryId !== dto.categoryId) {
        throw new BadRequestException('บริการย่อยไม่ตรงกับหมวดบริการที่เลือก');
      }
      const isInspection =
        subService.category.slug === INSPECTION_CATEGORY_SLUG;

      if (isInspection && dto.inspection?.appointmentAt) {
        const appointment = new Date(dto.inspection.appointmentAt).getTime();
        if (
          appointment < Date.now() + 60 * 60_000 ||
          appointment > Date.now() + 30 * 86_400_000
        ) {
          throw new BadRequestException(
            'นัดตรวจล่วงหน้าอย่างน้อย 1 ชั่วโมง และไม่เกิน 30 วัน',
          );
        }
      }
      const customer = await tx.customer.findUnique({
        where: { id: customerId },
        select: { deletedAt: true },
      });
      if (!customer || customer.deletedAt)
        throw new ForbiddenException('บัญชีนี้ใช้งานไม่ได้');
      const created = await tx.order.create({
        data: {
          orderNo: await this.generateOrderNo(tx),
          customerId,
          categoryId: dto.categoryId,
          subServiceId: dto.subServiceId,
          vehicleTypeId: dto.vehicleTypeId,
          pickupLat: dto.pickupLat,
          pickupLng: dto.pickupLng,
          pickupAddress: dto.pickupAddress,
          note: dto.note,
          priceEstimated: quote.price,
          commissionRate: commissionRate(),
          status: OrderStatus.CREATED,
          // บริการราคาเดียว (เช่น ตรวจรถ 1,990) ลูกค้ายอมรับราคาแล้วตอนจอง
          // ไม่ต้องรอช่างเสนอราคาหน้างาน
          ...(subService.fixedPrice
            ? {
                priceProposed: quote.price,
                quoteStatus: QuoteStatus.APPROVED,
                quoteRespondedAt: new Date(),
              }
            : {}),
          photos: dto.photoUrls?.length
            ? { create: dto.photoUrls.map((url) => ({ url })) }
            : undefined,
        },
      });
      if (isInspection) {
        await this.inspections.createForOrder(tx, created.id, dto.inspection);
      }
      return created;
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
        payment: PAYMENT_SUMMARY,
        rating: true,
        inspection: {
          select: {
            brand: true,
            model: true,
            year: true,
            appointmentAt: true,
            sellerName: true,
            sellerPhone: true,
            listingUrl: true,
            score: true,
            grade: true,
            verdict: true,
            submittedAt: true,
          },
        },
        provider: { select: PROVIDER_CARD_SELECT },
      },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    // ลิงก์แชร์ขอผ่าน POST /orders/:id/share เท่านั้น ไม่ติดไปกับข้อมูลงานที่ช่างก็เห็น
    const { shareToken: _shareToken, provider, ...rest } = order;
    return {
      ...rest,
      provider: provider ? presentProviderCard(order, provider) : null,
    };
  }

  async findAccessibleById(
    orderId: string,
    actor: { sub: string; role: Role },
  ) {
    const order = await this.findById(orderId);
    const isOwner =
      (actor.role === Role.CUSTOMER && order.customerId === actor.sub) ||
      (actor.role === Role.PROVIDER && order.providerId === actor.sub);

    if (!isOwner) {
      // ไม่เปิดเผยว่า order id นี้มีอยู่จริงหรือไม่ให้ผู้ใช้คนอื่นทราบ
      throw new NotFoundException('ไม่พบออเดอร์นี้');
    }
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
      include: {
        category: true,
        subService: true,
        photos: true,
        payment: PAYMENT_SUMMARY,
        inspection: {
          select: {
            brand: true,
            model: true,
            year: true,
            appointmentAt: true,
            sellerName: true,
            sellerPhone: true,
            submittedAt: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async cancelByCustomer(customerId: string, orderId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.customerId !== customerId) {
      throw new ForbiddenException('ยกเลิกออเดอร์ของคนอื่นไม่ได้');
    }
    // ยกเลิกได้เฉพาะก่อนช่างเริ่มทำงานจริง
    const cancellableBeforeWork =
      order.status === OrderStatus.CREATED ||
      order.status === OrderStatus.SEARCHING ||
      order.status === OrderStatus.NO_MATCH ||
      order.status === OrderStatus.MATCHED ||
      (order.status === OrderStatus.EN_ROUTE &&
        order.quoteStatus !== QuoteStatus.APPROVED);
    if (!cancellableBeforeWork) {
      throw new BadRequestException('ออเดอร์นี้ยกเลิกไม่ได้แล้ว');
    }

    const cancelled = await this.prisma.$transaction(async (tx) => {
      const changed = await tx.order.updateMany({
        where: {
          id: orderId,
          customerId,
          status: order.status,
          quoteStatus: order.quoteStatus,
        },
        data: { status: OrderStatus.CANCELLED, cancelledAt: new Date() },
      });
      if (changed.count !== 1)
        throw new ConflictException('สถานะงานเปลี่ยนแล้ว กรุณาโหลดใหม่');
      await tx.dispatchAttempt.updateMany({
        where: { orderId, status: DispatchStatus.OFFERED },
        data: { status: DispatchStatus.EXPIRED },
      });
      return tx.order.findUniqueOrThrow({ where: { id: orderId } });
    });
    void this.push.cancelledByCustomer(order.providerId, order);
    return cancelled;
  }

  async updateStatusByProvider(
    providerId: string,
    orderId: string,
    next: OrderStatus,
  ) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.providerId !== providerId) {
      throw new ForbiddenException('ออเดอร์นี้ไม่ใช่ของคุณ');
    }

    const requiredPrevious = PROVIDER_TRANSITIONS[next];
    if (!requiredPrevious || order.status !== requiredPrevious) {
      throw new BadRequestException('เปลี่ยนสถานะจากขั้นตอนปัจจุบันไม่ได้');
    }

    if (
      next === OrderStatus.IN_PROGRESS &&
      order.quoteStatus !== QuoteStatus.APPROVED
    ) {
      throw new BadRequestException('ต้องให้ลูกค้ายืนยันราคาก่อนเริ่มงาน');
    }

    const changed = await this.prisma.order.updateMany({
      where: {
        id: orderId,
        providerId,
        status: requiredPrevious,
        ...(next === OrderStatus.IN_PROGRESS
          ? {
              quoteStatus: QuoteStatus.APPROVED,
              quoteVersion: order.quoteVersion,
            }
          : {}),
      },
      data: { status: next },
    });
    if (changed.count !== 1)
      throw new ConflictException('สถานะงานเปลี่ยนแล้ว กรุณาโหลดใหม่');
    const updated = await this.prisma.order.findUniqueOrThrow({
      where: { id: orderId },
    });
    if (next === OrderStatus.EN_ROUTE) {
      void this.push.enRoute(order.customerId, order);
    } else if (next === OrderStatus.IN_PROGRESS) {
      void this.push.inProgress(order.customerId, order);
    }
    return updated;
  }

  async proposeQuote(
    providerId: string,
    orderId: string,
    dto: ProposeQuoteDto,
  ) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.providerId !== providerId) {
      throw new ForbiddenException('ออเดอร์นี้ไม่ใช่ของคุณ');
    }
    if (order.status !== OrderStatus.EN_ROUTE) {
      throw new BadRequestException('เสนอราคาได้เมื่อเดินทางถึงขั้นตอนหน้างาน');
    }

    const changed = await this.prisma.order.updateMany({
      where: {
        id: orderId,
        providerId,
        status: OrderStatus.EN_ROUTE,
        quoteVersion: order.quoteVersion,
        quoteStatus: { in: [QuoteStatus.NOT_REQUESTED, QuoteStatus.REJECTED] },
      },
      data: {
        priceProposed: dto.priceProposed,
        quoteNote: dto.note,
        quoteStatus: QuoteStatus.PENDING,
        quoteVersion: { increment: 1 },
        quoteProposedAt: new Date(),
        quoteRespondedAt: null,
      },
    });
    if (changed.count !== 1)
      throw new ConflictException(
        'มีราคาที่รอยืนยันหรือยืนยันแล้ว กรุณาโหลดใหม่',
      );
    const proposed = await this.prisma.order.findUniqueOrThrow({
      where: { id: orderId },
    });
    void this.push.quoteProposed(order.customerId, order, dto.priceProposed);
    return proposed;
  }

  async respondToQuote(
    customerId: string,
    orderId: string,
    approved: boolean,
    dto: RespondQuoteDto,
  ) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.customerId !== customerId) {
      throw new ForbiddenException('ยืนยันราคาของออเดอร์คนอื่นไม่ได้');
    }
    if (
      order.status !== OrderStatus.EN_ROUTE ||
      order.quoteStatus !== QuoteStatus.PENDING ||
      order.priceProposed === null
    ) {
      throw new BadRequestException('ไม่มีราคาที่กำลังรอการยืนยัน');
    }

    const changed = await this.prisma.order.updateMany({
      where: {
        id: orderId,
        customerId,
        status: OrderStatus.EN_ROUTE,
        quoteStatus: QuoteStatus.PENDING,
        quoteVersion: dto.quoteVersion,
        priceProposed: dto.priceProposed,
      },
      data: {
        quoteStatus: approved ? QuoteStatus.APPROVED : QuoteStatus.REJECTED,
        quoteRespondedAt: new Date(),
      },
    });
    if (changed.count !== 1)
      throw new ConflictException(
        'ราคาเปลี่ยนแล้ว กรุณาโหลดราคาใหม่ก่อนยืนยัน',
      );
    const answered = await this.prisma.order.findUniqueOrThrow({
      where: { id: orderId },
    });
    void this.push.quoteAnswered(order.providerId, order, approved);
    return answered;
  }

  /** ช่างปิดงานด้วยราคาที่ลูกค้ายืนยันแล้ว ระบบสร้างรายการชำระเงินรอลูกค้าจ่าย */
  async completeByProvider(providerId: string, orderId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (order.providerId !== providerId) {
      throw new ForbiddenException('ออเดอร์นี้ไม่ใช่ของคุณ');
    }
    if (order.status !== OrderStatus.IN_PROGRESS) {
      throw new BadRequestException('ต้องอยู่ในสถานะกำลังดำเนินการก่อนปิดงาน');
    }
    if (
      order.quoteStatus !== QuoteStatus.APPROVED ||
      order.priceProposed === null
    ) {
      throw new BadRequestException('ไม่พบราคาที่ลูกค้ายืนยันแล้ว');
    }
    await this.inspections.assertSubmittedIfRequired(orderId);

    await this.prisma.$transaction(async (tx) => {
      const completed = await tx.order.updateMany({
        where: {
          id: orderId,
          providerId,
          status: OrderStatus.IN_PROGRESS,
          quoteStatus: QuoteStatus.APPROVED,
        },
        data: {
          status: OrderStatus.COMPLETED,
          priceFinal: order.priceProposed!,
          completedAt: new Date(),
        },
      });
      if (completed.count !== 1) {
        throw new BadRequestException('ออเดอร์นี้ถูกปิดงานไปแล้ว');
      }

      await tx.payment.upsert({
        where: { orderId },
        create: {
          orderId,
          amount: order.priceProposed!,
          status: PaymentStatus.PENDING,
        },
        update: { amount: order.priceProposed! },
      });
    });

    void this.push.completed(order.customerId, order, order.priceProposed);
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

    return serializable(this.prisma, async (tx) => {
      const existing = await tx.rating.findUnique({ where: { orderId } });
      if (existing) throw new BadRequestException('ออเดอร์นี้ให้คะแนนไปแล้ว');
      const rating = await tx.rating.create({
        data: { orderId, score: dto.score, comment: dto.comment },
      });

      const totals = await tx.rating.aggregate({
        where: { order: { providerId } },
        _avg: { score: true },
        _count: { _all: true },
      });
      await tx.provider.update({
        where: { id: providerId },
        data: {
          ratingAvg: totals._avg.score ?? 0,
          ratingCount: totals._count._all,
        },
      });

      return rating;
    }).catch((error) => {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new BadRequestException('ออเดอร์นี้ให้คะแนนไปแล้ว');
      }
      throw error;
    });
  }
}
