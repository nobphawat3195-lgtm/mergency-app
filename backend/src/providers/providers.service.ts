import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Provider, ProviderStatus } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { UploadsService } from '../uploads/uploads.service';
import { AdminAlertService } from '../notifications/admin-alert.service';
import {
  RegisterProviderDto,
  UpdateLocationDto,
  UpdatePayoutInfoDto,
} from './dto/provider.dto';

@Injectable()
export class ProvidersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly uploads: UploadsService,
    private readonly adminAlert: AdminAlertService,
  ) {}

  /** uploaderId = sub ของโทเคนที่ใช้ขอ presign (ช่างที่ยังไม่สมัครคือ pending:<เบอร์>) */
  async register(
    phone: string,
    dto: RegisterProviderDto,
    uploaderId: string,
  ): Promise<Provider> {
    this.uploads.assertOwnedUploads(
      dto.toolPhotoUrls,
      uploaderId,
      'PROVIDER_TOOL',
    );
    const existing = await this.prisma.provider.findUnique({
      where: { phone },
    });
    if (existing) {
      throw new BadRequestException('เบอร์นี้ลงทะเบียนเป็นช่างไว้แล้ว');
    }

    const provider = await this.prisma.provider.create({
      data: {
        phone,
        realName: dto.realName,
        nickname: dto.nickname,
        experienceYears: dto.experienceYears,
        shopName: dto.shopName,
        facebookPage: dto.facebookPage,
        baseLat: dto.baseLat,
        baseLng: dto.baseLng,
        openMinute: dto.openMinute,
        closeMinute: dto.closeMinute,
        status: ProviderStatus.PENDING,
        serviceCategories: {
          create: dto.categoryIds.map((categoryId) => ({ categoryId })),
        },
        vehicleTypes: {
          create: dto.vehicleTypeIds.map((vehicleTypeId) => ({
            vehicleTypeId,
          })),
        },
        toolPhotos: {
          create: dto.toolPhotoUrls.map((url) => ({ url })),
        },
      },
    });
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
    return this.prisma.provider.update({
      where: { id: providerId },
      data: {
        currentLat: dto.lat,
        currentLng: dto.lng,
        lastSeenAt: new Date(),
      },
    });
  }

  async heartbeat(providerId: string): Promise<{ ok: true }> {
    await this.requireVerified(providerId);
    await this.prisma.provider.update({
      where: { id: providerId },
      data: { lastSeenAt: new Date() },
    });
    return { ok: true };
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
