import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrderStatus, Provider, ProviderStatus } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { UploadsService } from '../uploads/uploads.service';
import { AdminAlertService } from '../notifications/admin-alert.service';
import { OrderEventsService } from '../notifications/order-events.service';
import {
  RegisterProviderDto,
  UpdateLocationDto,
  UpdatePayoutInfoDto,
  UpdatePublicProfileDto,
} from './dto/provider.dto';

@Injectable()
export class ProvidersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly uploads: UploadsService,
    private readonly adminAlert: AdminAlertService,
    private readonly events: OrderEventsService,
  ) {}

  /**
   * ยื่นใบสมัคร uploaderId = sub ของโทเคนที่ใช้ขอ presign (ช่างที่ยังไม่สมัครคือ pending:<เบอร์>)
   * ใบสมัครที่ถูกปฏิเสธ (REJECTED) ส่งใหม่ได้ ข้อมูลเดิมถูกแทนที่และกลับไปรอตรวจ
   */
  async register(
    phone: string,
    dto: RegisterProviderDto,
    uploaderId: string,
  ): Promise<Provider> {
    this.uploads.assertOwnedUploads(
      [...dto.toolPhotoUrls, dto.photoUrl],
      uploaderId,
      'PROVIDER_TOOL',
    );
    const existing = await this.prisma.provider.findUnique({
      where: { phone },
    });
    if (existing && existing.status !== ProviderStatus.REJECTED) {
      throw new BadRequestException('เบอร์นี้ลงทะเบียนเป็นช่างไว้แล้ว');
    }

    const data = {
      realName: dto.realName,
      nickname: dto.nickname,
      experienceYears: dto.experienceYears,
      shopName: dto.shopName ?? null,
      facebookPage: dto.facebookPage ?? null,
      baseLat: dto.baseLat,
      baseLng: dto.baseLng,
      openMinute: dto.openMinute,
      closeMinute: dto.closeMinute,
      photoUrl: dto.photoUrl,
      vehiclePlate: dto.vehiclePlate.trim().toUpperCase(),
      vehicleDesc: dto.vehicleDesc?.trim() || null,
      status: ProviderStatus.PENDING,
      reviewNote: null,
      reviewedAt: null,
    };
    const relations = {
      serviceCategories: {
        create: dto.categoryIds.map((categoryId) => ({ categoryId })),
      },
      vehicleTypes: {
        create: dto.vehicleTypeIds.map((vehicleTypeId) => ({ vehicleTypeId })),
      },
      toolPhotos: {
        create: dto.toolPhotoUrls.map((url) => ({ url })),
      },
    };

    let replacedPhotos: string[] = [];
    const provider = existing
      ? await this.prisma.$transaction(async (tx) => {
          const old = await tx.providerToolPhoto.findMany({
            where: { providerId: existing.id },
            select: { url: true },
          });
          replacedPhotos = [
            ...old.map((photo) => photo.url),
            ...(existing.photoUrl ? [existing.photoUrl] : []),
          ].filter(
            (url) => url !== dto.photoUrl && !dto.toolPhotoUrls.includes(url),
          );
          await tx.providerServiceCategory.deleteMany({
            where: { providerId: existing.id },
          });
          await tx.providerVehicleType.deleteMany({
            where: { providerId: existing.id },
          });
          await tx.providerToolPhoto.deleteMany({
            where: { providerId: existing.id },
          });
          return tx.provider.update({
            where: { id: existing.id },
            data: { ...data, ...relations },
          });
        })
      : await this.prisma.provider.create({
          data: { phone, ...data, ...relations },
        });
    if (replacedPhotos.length > 0) {
      await this.uploads.deleteUploads(replacedPhotos);
    }
    void this.adminAlert.providerApplied(provider.nickname);
    return provider;
  }

  async getMe(providerId: string) {
    const provider = await this.prisma.provider.findUnique({
      where: { id: providerId },
      include: {
        serviceCategories: { include: { category: true } },
        vehicleTypes: { include: { vehicleType: true } },
        toolPhotos: true,
      },
    });
    if (!provider) throw new NotFoundException('ไม่พบข้อมูลช่าง');
    return provider;
  }

  private async requireVerified(providerId: string): Promise<Provider> {
    const provider = await this.prisma.provider.findUnique({
      where: { id: providerId },
    });
    if (!provider) throw new NotFoundException('ไม่พบข้อมูลช่าง');
    if (provider.status !== ProviderStatus.VERIFIED) {
      throw new ForbiddenException('บัญชีช่างยังไม่ได้รับการอนุมัติ');
    }
    return provider;
  }

  async setOnline(providerId: string, isOnline: boolean): Promise<Provider> {
    await this.requireVerified(providerId);
    return this.prisma.provider.update({
      where: { id: providerId },
      data: { isOnline, lastSeenAt: new Date() },
    });
  }

  async updateLocation(
    providerId: string,
    dto: UpdateLocationDto,
  ): Promise<Provider> {
    await this.requireVerified(providerId);
    const provider = await this.prisma.provider.update({
      where: { id: providerId },
      data: {
        currentLat: dto.lat,
        currentLng: dto.lng,
        locationAt: new Date(),
        lastSeenAt: new Date(),
      },
    });
    // ลูกค้าที่เปิดหน้าติดตามงานอยู่เห็นช่างขยับทันที
    const active = await this.prisma.order.findFirst({
      where: {
        providerId,
        status: {
          in: [
            OrderStatus.MATCHED,
            OrderStatus.EN_ROUTE,
            OrderStatus.IN_PROGRESS,
          ],
        },
      },
      select: { id: true },
    });
    if (active) this.events.emit(active.id, 'LOCATION');
    return provider;
  }

  async heartbeat(providerId: string): Promise<{ ok: true }> {
    await this.requireVerified(providerId);
    await this.prisma.provider.update({
      where: { id: providerId },
      data: { lastSeenAt: new Date() },
    });
    return { ok: true };
  }

  /** ข้อมูลในการ์ดช่างที่ลูกค้าเห็น: ค่า "" = ลบ, ไม่ส่งฟิลด์ = ไม่เปลี่ยน */
  async updatePublicProfile(
    providerId: string,
    dto: UpdatePublicProfileDto,
  ): Promise<Provider> {
    const current = await this.prisma.provider.findUnique({
      where: { id: providerId },
      select: { photoUrl: true },
    });
    if (!current) throw new NotFoundException('ไม่พบข้อมูลช่าง');

    const clean = (value: string | undefined) =>
      value === undefined ? undefined : value.trim() || null;
    const photoUrl = clean(dto.photoUrl);
    if (photoUrl) {
      this.uploads.assertOwnedUploads([photoUrl], providerId, 'PROVIDER_TOOL');
    }

    const updated = await this.prisma.provider.update({
      where: { id: providerId },
      data: {
        photoUrl,
        vehicleDesc: clean(dto.vehicleDesc),
        vehiclePlate: clean(dto.vehiclePlate)?.toUpperCase(),
      },
    });
    // เปลี่ยนรูปแล้วลบรูปเก่า ไม่เก็บรูปหน้าช่างไว้เกินจำเป็น
    const old = current.photoUrl;
    if (photoUrl !== undefined && old && old !== photoUrl) {
      const alsoToolPhoto = await this.prisma.providerToolPhoto.count({
        where: { providerId, url: old },
      });
      if (alsoToolPhoto === 0) await this.uploads.deleteUploads([old]);
    }
    return updated;
  }

  async updatePayoutInfo(
    providerId: string,
    dto: UpdatePayoutInfoDto,
  ): Promise<Provider> {
    return this.prisma.provider.update({
      where: { id: providerId },
      data: {
        bankName: dto.bankName,
        bankAccountName: dto.bankAccountName,
        bankAccountNumber: dto.bankAccountNumber,
        promptPayId: dto.promptPayId,
      },
    });
  }
}
