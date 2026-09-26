import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, WalletEntryType, WithdrawalStatus } from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { AdminAlertService } from '../notifications/admin-alert.service';
import { formatBaht } from '../common/money';

@Injectable()
export class WalletService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly adminAlert: AdminAlertService,
  ) {}

  /** ยอดคงเหลือ = ผลรวมทุกรายการใน ledger ของช่างคนนั้น */
  async getBalance(providerId: string): Promise<number> {
    const result = await this.prisma.walletEntry.aggregate({
      where: { providerId },
      _sum: { amount: true },
    });
    return result._sum.amount ?? 0;
  }

  listEntries(providerId: string) {
    return this.prisma.walletEntry.findMany({
      where: { providerId },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  /**
   * เครดิตรายได้เข้ากระเป๋าช่างหลังลูกค้าชำระเงินสำเร็จ
   * หักคอมมิชชันตามเรตที่บันทึกไว้ในออเดอร์ แล้วเครดิตเฉพาะยอดสุทธิ
   * เรียกซ้ำด้วยออเดอร์เดิมจะไม่เครดิตซ้ำ
   */
  async creditOrderEarning(orderId: string): Promise<void> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { payment: true },
    });

    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (!order.providerId) {
      throw new BadRequestException('ออเดอร์นี้ไม่มีช่างรับผิดชอบ');
    }

    const gross = order.priceFinal ?? order.priceEstimated;
    const commission = Math.round(gross * order.commissionRate);
    const net = gross - commission;
    const providerId = order.providerId;

    try {
      await this.prisma.walletEntry.create({
        data: {
          idempotencyKey: `order-earning:${orderId}`,
          providerId,
          type: WalletEntryType.ORDER_EARNING,
          amount: net,
          orderId,
          memo: `รายได้งาน ${order.orderNo}`,
        },
      });
    } catch (error) {
      // webhook/payment confirmation อาจมาซ้ำหรือชนกัน ให้เครดิตเพียงครั้งเดียว
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        return;
      }
      throw error;
    }
  }

  /**
   * งานที่ลูกค้าจ่ายเงินสดให้ช่าง: ช่างถือเงินเต็มจำนวนอยู่แล้ว
   * จึงบันทึกค่าธรรมเนียมที่ช่างต้องคืนบริษัทเป็นยอดติดลบ (หักจากรายได้งานพร้อมเพย์ครั้งถัดไป)
   * ห้ามเครดิตรายได้ให้ซ้ำ ไม่งั้นช่างจะเบิกเงินที่บริษัทไม่เคยได้รับ
   */
  async chargeCashCommission(orderId: string): Promise<void> {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (!order.providerId) {
      throw new BadRequestException('ออเดอร์นี้ไม่มีช่างรับผิดชอบ');
    }
    const gross = order.priceFinal ?? order.priceEstimated;
    const commission = Math.round(gross * order.commissionRate);
    try {
      await this.prisma.walletEntry.create({
        data: {
          idempotencyKey: `cash-commission:${orderId}`,
          providerId: order.providerId,
          type: WalletEntryType.COMMISSION_DUE,
          amount: -commission,
          orderId,
          memo: `ค่าบริการแพลตฟอร์ม งาน ${order.orderNo} (ลูกค้าจ่ายเงินสดกับช่าง)`,
        },
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        return;
      }
      throw error;
    }
  }

  /**
   * ช่างกดขอเบิกเงิน — กันยอดออกจากกระเป๋าทันทีเพื่อไม่ให้เบิกซ้อนเกินยอดคงเหลือ
   * ใช้ Serializable กันกรณีกดเบิกพร้อมกันหลายครั้ง
   */
  async requestWithdrawal(providerId: string, amount: number) {
    if (amount <= 0) {
      throw new BadRequestException('จำนวนเงินที่ขอเบิกต้องมากกว่า 0');
    }

    const withdrawal = await this.prisma.$transaction(
      async (tx) => {
        const provider = await tx.provider.findUnique({
          where: { id: providerId },
        });
        if (!provider) throw new NotFoundException('ไม่พบข้อมูลช่าง');

        const hasPayoutInfo =
          Boolean(provider.promptPayId) ||
          Boolean(provider.bankAccountNumber && provider.bankName);
        if (!hasPayoutInfo) {
          throw new BadRequestException(
            'กรุณากรอกข้อมูลบัญชีรับเงินก่อนขอเบิก',
          );
        }

        const balanceResult = await tx.walletEntry.aggregate({
          where: { providerId },
          _sum: { amount: true },
        });
        const balance = balanceResult._sum.amount ?? 0;

        if (balance < amount) {
          throw new BadRequestException('ยอดเงินในกระเป๋าไม่เพียงพอ');
        }

        const withdrawal = await tx.withdrawalRequest.create({
          data: {
            providerId,
            amount,
            status: WithdrawalStatus.REQUESTED,
            bankName: provider.bankName,
            bankAccountName: provider.bankAccountName,
            bankAccountNumber: provider.bankAccountNumber,
            promptPayId: provider.promptPayId,
          },
        });

        await tx.walletEntry.create({
          data: {
            providerId,
            type: WalletEntryType.WITHDRAWAL,
            amount: -amount,
            withdrawalId: withdrawal.id,
            memo: 'กันยอดสำหรับคำขอเบิกเงิน',
          },
        });

        return { withdrawal, nickname: provider.nickname };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
    void this.adminAlert.withdrawalRequested(
      withdrawal.nickname,
      formatBaht(amount),
    );
    return withdrawal.withdrawal;
  }

  listWithdrawals(providerId: string) {
    return this.prisma.withdrawalRequest.findMany({
      where: { providerId },
      orderBy: { requestedAt: 'desc' },
    });
  }

  /** แอดมินยืนยันว่าโอนเงินจริงแล้ว ยอดถูกกันไว้ตั้งแต่ตอนขอเบิก จึงไม่ต้องตัดซ้ำ */
  async markTransferred(withdrawalId: string, slipUrl?: string, note?: string) {
    const withdrawal = await this.prisma.withdrawalRequest.findUnique({
      where: { id: withdrawalId },
    });
    if (!withdrawal) throw new NotFoundException('ไม่พบคำขอเบิกเงินนี้');
    if (withdrawal.status !== WithdrawalStatus.REQUESTED) {
      throw new BadRequestException('คำขอนี้ถูกดำเนินการไปแล้ว');
    }

    return this.prisma.withdrawalRequest.update({
      where: { id: withdrawalId },
      data: {
        status: WithdrawalStatus.TRANSFERRED,
        transferredAt: new Date(),
        transferSlip: slipUrl,
        adminNote: note,
      },
    });
  }

  /** แอดมินปฏิเสธคำขอ ต้องคืนยอดที่กันไว้กลับเข้ากระเป๋า */
  async rejectWithdrawal(withdrawalId: string, note?: string) {
    return this.prisma.$transaction(async (tx) => {
      const withdrawal = await tx.withdrawalRequest.findUnique({
        where: { id: withdrawalId },
      });
      if (!withdrawal) throw new NotFoundException('ไม่พบคำขอเบิกเงินนี้');
      if (withdrawal.status !== WithdrawalStatus.REQUESTED) {
        throw new BadRequestException('คำขอนี้ถูกดำเนินการไปแล้ว');
      }

      await tx.walletEntry.create({
        data: {
          providerId: withdrawal.providerId,
          type: WalletEntryType.ADJUSTMENT,
          amount: withdrawal.amount,
          withdrawalId: withdrawal.id,
          memo: 'คืนยอดจากคำขอเบิกที่ถูกปฏิเสธ',
        },
      });

      return tx.withdrawalRequest.update({
        where: { id: withdrawalId },
        data: { status: WithdrawalStatus.REJECTED, adminNote: note },
      });
    });
  }
}
