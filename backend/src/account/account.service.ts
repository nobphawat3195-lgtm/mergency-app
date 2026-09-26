import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  OrderStatus,
  PaymentStatus,
  ProviderStatus,
  Role,
  WithdrawalStatus,
} from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { WalletService } from '../wallet/wallet.service';
import { UploadsService } from '../uploads/uploads.service';

/** งานที่ยังไม่จบ ลบบัญชีระหว่างนี้ไม่ได้ อีกฝ่ายยังต้องติดต่อกันอยู่ */
const ACTIVE_ORDER_STATUSES: OrderStatus[] = [
  OrderStatus.CREATED,
  OrderStatus.SEARCHING,
  OrderStatus.MATCHED,
  OrderStatus.EN_ROUTE,
  OrderStatus.IN_PROGRESS,
];

const SETTLED_PAYMENT: PaymentStatus[] = [
  PaymentStatus.PAID,
  PaymentStatus.REFUNDED,
];

/**
 * ลบบัญชีตามคำขอผู้ใช้ (App Store 5.1.1(v) และสิทธิ์ขอลบข้อมูลตาม PDPA)
 *
 * ลบ/ปิดบังข้อมูลที่ระบุตัวตนได้ทั้งหมด แต่เก็บตัวเลขธุรกรรม (ราคา การชำระเงิน รายได้ช่าง)
 * ไว้ตามหน้าที่ทางบัญชีและภาษี เบอร์โทรเดิมสมัครใหม่ได้ทันทีเป็นบัญชีใหม่
 */
@Injectable()
export class AccountService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
    private readonly uploads: UploadsService,
  ) {}

  async deleteAccount(userId: string, role: Role): Promise<{ deleted: true }> {
    if (role === Role.CUSTOMER) await this.deleteCustomer(userId);
    else if (role === Role.PROVIDER) await this.deleteProvider(userId);
    else throw new NotFoundException('ไม่พบบัญชีนี้');
    return { deleted: true };
  }

  private async deleteCustomer(customerId: string) {
    const customer = await this.prisma.customer.findUnique({
      where: { id: customerId },
    });
    if (!customer || customer.deletedAt) {
      throw new NotFoundException('ไม่พบบัญชีนี้');
    }

    const active = await this.prisma.order.count({
      where: { customerId, status: { in: ACTIVE_ORDER_STATUSES } },
    });
    if (active > 0) {
      throw new ConflictException(
        'ยังมีงานที่กำลังดำเนินการ ยกเลิกหรือรอให้งานเสร็จก่อนลบบัญชี',
      );
    }
    const unpaid = await this.prisma.order.count({
      where: {
        customerId,
        status: OrderStatus.COMPLETED,
        OR: [
          { payment: null },
          { payment: { status: { notIn: SETTLED_PAYMENT } } },
        ],
      },
    });
    if (unpaid > 0) {
      throw new ConflictException(
        'ยังมีงานที่ยังไม่ได้ชำระเงิน ชำระให้เรียบร้อยก่อนลบบัญชี',
      );
    }

    const photos = await this.prisma.$transaction(async (tx) => {
      const orders = await tx.order.findMany({
        where: { customerId },
        select: { id: true },
      });
      const orderIds = orders.map((order) => order.id);
      const orderPhotos = await tx.orderPhoto.findMany({
        where: { orderId: { in: orderIds } },
        select: { url: true },
      });
      await tx.orderPhoto.deleteMany({ where: { orderId: { in: orderIds } } });
      // สลิปโอนเงินมีชื่อและเลขบัญชีของลูกค้า ลบรูป เหลือไว้แค่ยอดและสถานะการชำระ
      const slips = await tx.payment.findMany({
        where: { orderId: { in: orderIds }, slipUrl: { not: null } },
        select: { slipUrl: true },
      });
      await tx.payment.updateMany({
        where: { orderId: { in: orderIds } },
        data: { slipUrl: null },
      });
      await tx.order.updateMany({
        where: { customerId },
        data: { pickupAddress: null, note: null },
      });
      // ข้อมูลผู้ขายรถในงานตรวจรถเป็นข้อมูลที่ลูกค้าให้มา ลบไปพร้อมกัน
      await tx.inspectionReport.updateMany({
        where: { orderId: { in: orderIds } },
        data: { sellerName: null, sellerPhone: null, listingUrl: null },
      });
      await tx.rating.updateMany({
        where: { orderId: { in: orderIds } },
        data: { comment: null },
      });
      await tx.otpCode.deleteMany({
        where: { phone: customer.phone, role: Role.CUSTOMER },
      });
      await tx.deviceToken.deleteMany({
        where: { role: Role.CUSTOMER, userId: customerId },
      });
      await tx.customer.update({
        where: { id: customerId },
        data: {
          phone: `deleted:${customerId}`,
          name: null,
          deletedAt: new Date(),
        },
      });
      return [
        ...orderPhotos.map((photo) => photo.url),
        ...slips.map((slip) => slip.slipUrl as string),
      ];
    });
    // ลบไฟล์หลัง commit แล้วเท่านั้น ถ้า transaction ล้มรูปต้องยังอยู่ครบ
    await this.uploads.deleteUploads(photos);
  }

  private async deleteProvider(providerId: string) {
    const provider = await this.prisma.provider.findUnique({
      where: { id: providerId },
    });
    if (!provider || provider.deletedAt) {
      throw new NotFoundException('ไม่พบบัญชีนี้');
    }

    const active = await this.prisma.order.count({
      where: { providerId, status: { in: ACTIVE_ORDER_STATUSES } },
    });
    if (active > 0) {
      throw new ConflictException(
        'ยังมีงานที่รับไว้และยังไม่ปิด ปิดงานให้เรียบร้อยก่อนลบบัญชี',
      );
    }
    const pendingWithdrawals = await this.prisma.withdrawalRequest.count({
      where: { providerId, status: WithdrawalStatus.REQUESTED },
    });
    if (pendingWithdrawals > 0) {
      throw new ConflictException(
        'มีคำขอเบิกเงินที่รอโอนอยู่ รอให้โอนเสร็จก่อนลบบัญชี',
      );
    }
    const balance = await this.wallet.getBalance(providerId);
    if (balance > 0) {
      throw new ConflictException(
        'ยังมียอดเงินคงเหลือในกระเป๋า กดขอเบิกเงินให้หมดก่อนลบบัญชี',
      );
    }

    const toolPhotos = await this.prisma.providerToolPhoto.findMany({
      where: { providerId },
      select: { url: true },
    });
    await this.prisma.$transaction(async (tx) => {
      await tx.providerToolPhoto.deleteMany({ where: { providerId } });
      await tx.dispatchAttempt.deleteMany({
        where: { providerId, status: 'OFFERED' },
      });
      await tx.otpCode.deleteMany({
        where: { phone: provider.phone, role: Role.PROVIDER },
      });
      await tx.deviceToken.deleteMany({
        where: { role: Role.PROVIDER, userId: providerId },
      });
      await tx.provider.update({
        where: { id: providerId },
        data: {
          phone: `deleted:${providerId}`,
          realName: 'บัญชีที่ลบแล้ว',
          nickname: '',
          shopName: null,
          facebookPage: null,
          bankName: null,
          bankAccountName: null,
          bankAccountNumber: null,
          promptPayId: null,
          currentLat: null,
          currentLng: null,
          isOnline: false,
          status: ProviderStatus.SUSPENDED,
          deletedAt: new Date(),
        },
      });
    });
    await this.uploads.deleteUploads(toolPhotos.map((photo) => photo.url));
  }

  /** ใช้ตรวจโทเคนทุกคำขอ: บัญชีที่ลบแล้วใช้โทเคนเก่าต่อไม่ได้ */
  async isActive(userId: string, role: Role): Promise<boolean> {
    if (role === Role.CUSTOMER) {
      const customer = await this.prisma.customer.findUnique({
        where: { id: userId },
        select: { deletedAt: true },
      });
      return customer !== null && customer.deletedAt === null;
    }
    if (role === Role.PROVIDER) {
      // โทเคนช่วงยังไม่กรอกใบสมัครใช้ sub แบบ pending:<phone>
      if (userId.startsWith('pending:')) return true;
      const provider = await this.prisma.provider.findUnique({
        where: { id: userId },
        select: { deletedAt: true },
      });
      return provider !== null && provider.deletedAt === null;
    }
    return true;
  }
}
