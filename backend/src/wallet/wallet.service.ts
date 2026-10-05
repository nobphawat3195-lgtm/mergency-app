import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  Prisma,
  SettlementStatus,
  WalletEntryType,
  WithdrawalStatus,
} from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';
import { AdminAlertService } from '../notifications/admin-alert.service';
import { PushService } from '../notifications/push.service';
import { UploadsService } from '../uploads/uploads.service';
import { serializable } from '../common/transaction';
import { formatBaht } from '../common/money';
import { cashDebtLimit } from '../common/constants';
import { promptPayPayload } from '../payments/promptpay-qr';

export interface DebtStatus {
  /** ยอดกระเป๋า (สตางค์) ติดลบได้ */
  balance: number;
  /** ค่าบริการที่ค้างบริษัท = ส่วนที่ติดลบ (สตางค์) */
  owed: number;
  /** เพดานค่าบริการค้าง (สตางค์) */
  limit: number;
  /** ค้างเกินเพดาน: เปิดรับงานไม่ได้ */
  blocked: boolean;
  /** สลิปโอนคืนที่รอแอดมินตรวจ */
  pendingSettlement: { id: string; amount: number; createdAt: Date } | null;
  /** สลิปล่าสุดที่ถูกปฏิเสธ (ถ้ายังไม่มีรายการใหม่) ให้ช่างเห็นเหตุผล */
  lastRejectReason: string | null;
}

@Injectable()
export class WalletService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly adminAlert: AdminAlertService,
    private readonly push: PushService,
    private readonly uploads: UploadsService,
  ) {}

  /** ยอดคงเหลือ = ผลรวมทุกรายการใน ledger ของช่างคนนั้น */
  async getBalance(providerId: string): Promise<number> {
    const result = await this.prisma.walletEntry.aggregate({
      where: { providerId },
      _sum: { amount: true },
    });
    return result._sum.amount ?? 0;
  }

  /** สถานะค่าบริการค้างของช่าง ใช้ทั้งในแอปช่างและตอนเช็กก่อนเปิดรับงาน */
  async getDebtStatus(providerId: string): Promise<DebtStatus> {
    const [balance, latest] = await Promise.all([
      this.getBalance(providerId),
      this.prisma.commissionSettlement.findFirst({
        where: { providerId },
        orderBy: { createdAt: 'desc' },
      }),
    ]);
    const limit = cashDebtLimit();
    const owed = Math.max(0, -balance);
    return {
      balance,
      owed,
      limit,
      blocked: owed > limit,
      pendingSettlement:
        latest?.status === SettlementStatus.PENDING
          ? {
              id: latest.id,
              amount: latest.amount,
              createdAt: latest.createdAt,
            }
          : null,
      lastRejectReason:
        latest?.status === SettlementStatus.REJECTED
          ? latest.rejectReason
          : null,
    };
  }

  /** เรียกก่อนเปิดรับงานหรือกดรับงาน: ค้างค่าบริการเกินเพดานต้องโอนคืนก่อน */
  async assertCanTakeJobs(
    providerId: string,
    tx?: Prisma.TransactionClient,
  ): Promise<void> {
    const debt = tx
      ? await tx.walletEntry
          .aggregate({ where: { providerId }, _sum: { amount: true } })
          .then((sum) => {
            const owed = Math.max(0, -(sum._sum.amount ?? 0));
            const limit = cashDebtLimit();
            return { owed, limit, blocked: owed > limit };
          })
      : await this.getDebtStatus(providerId);
    if (!debt.blocked) return;
    throw new ForbiddenException(
      `ค้างค่าบริการแพลตฟอร์ม ${formatBaht(debt.owed)} เกินเพดาน ${formatBaht(debt.limit)} ` +
        'กรุณาโอนชำระในหน้ากระเป๋าเงินก่อนเปิดรับงาน',
    );
  }

  /** QR พร้อมเพย์ของบริษัท ล็อกยอดเท่ากับค่าบริการที่ค้างทั้งหมด */
  async settlementQr(providerId: string) {
    const promptPayId = process.env.PROMPTPAY_ID?.trim();
    const payeeName = process.env.PROMPTPAY_NAME?.trim() || null;
    if (!promptPayId) {
      throw new BadRequestException(
        'ยังไม่ได้ตั้งบัญชีพร้อมเพย์รับเงิน กรุณาติดต่อทีมงาน',
      );
    }
    const debt = await this.getDebtStatus(providerId);
    if (debt.owed <= 0) {
      throw new BadRequestException('ไม่มีค่าบริการค้างชำระ');
    }
    return {
      amount: debt.owed,
      qrPayload: promptPayPayload(promptPayId, debt.owed),
      payeeName,
      promptPayId,
    };
  }

  /**
   * ช่างแนบสลิปโอนค่าบริการค้าง ยอดยังไม่เปลี่ยนจนกว่าแอดมินตรวจเงินเข้าบัญชีจริงแล้วกดยืนยัน
   * มีสลิปรอตรวจได้ครั้งละหนึ่งใบ
   */
  async submitSettlement(providerId: string, slipUrl: string) {
    this.uploads.assertOwnedUploads([slipUrl], providerId, 'PAYMENT_SLIP');
    const { settlement, nickname } = await serializable(
      this.prisma,
      async (tx) => {
        const pending = await tx.commissionSettlement.findFirst({
          where: { providerId, status: SettlementStatus.PENDING },
          select: { id: true },
        });
        if (pending) {
          throw new BadRequestException(
            'มีสลิปที่รอทีมงานตรวจอยู่แล้ว กรุณารอผลก่อน',
          );
        }
        const sum = await tx.walletEntry.aggregate({
          where: { providerId },
          _sum: { amount: true },
        });
        const owed = Math.max(0, -(sum._sum.amount ?? 0));
        if (owed <= 0) {
          throw new BadRequestException('ไม่มีค่าบริการค้างชำระ');
        }
        const provider = await tx.provider.findUniqueOrThrow({
          where: { id: providerId },
          select: { nickname: true },
        });
        const settlement = await tx.commissionSettlement.create({
          data: { providerId, amount: owed, slipUrl },
        });
        return { settlement, nickname: provider.nickname };
      },
    );
    void this.adminAlert.settlementSubmitted(
      nickname,
      formatBaht(settlement.amount),
    );
    return settlement;
  }

  listSettlementsForReview() {
    return this.prisma.commissionSettlement.findMany({
      where: { status: SettlementStatus.PENDING },
      include: {
        provider: { select: { nickname: true, realName: true, phone: true } },
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  /** แอดมินเห็นเงินเข้าบัญชีแล้ว: ลงยอดคืนในกระเป๋าครั้งเดียว กดซ้ำได้ผลเหมือนเดิม */
  async confirmSettlement(settlementId: string) {
    const settlement = await this.prisma.commissionSettlement.findUnique({
      where: { id: settlementId },
    });
    if (!settlement) throw new NotFoundException('ไม่พบรายการโอนคืนนี้');
    if (settlement.status === SettlementStatus.CONFIRMED) {
      return { status: SettlementStatus.CONFIRMED };
    }
    if (settlement.status !== SettlementStatus.PENDING) {
      throw new BadRequestException('รายการนี้ถูกปฏิเสธไปแล้ว');
    }
    const confirmed = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.commissionSettlement.updateMany({
        where: { id: settlementId, status: SettlementStatus.PENDING },
        data: { status: SettlementStatus.CONFIRMED, reviewedAt: new Date() },
      });
      if (updated.count !== 1) return false;
      await tx.walletEntry.create({
        data: {
          idempotencyKey: `settlement:${settlementId}`,
          providerId: settlement.providerId,
          type: WalletEntryType.COMMISSION_PAID,
          amount: settlement.amount,
          memo: 'โอนชำระค่าบริการแพลตฟอร์มที่ค้าง',
        },
      });
      return true;
    });
    if (confirmed) {
      void this.push.providerWalletNotice(
        settlement.providerId,
        'ได้รับค่าบริการที่โอนคืนแล้ว',
        `ทีมงานยืนยันยอด ${formatBaht(settlement.amount)} แล้ว เปิดรับงานต่อได้เลย`,
      );
    }
    return { status: SettlementStatus.CONFIRMED };
  }

  /** สลิปไม่ถูกต้องหรือเงินไม่เข้า: ช่างเห็นเหตุผลและแนบสลิปใหม่ได้ */
  async rejectSettlement(settlementId: string, reason: string) {
    const settlement = await this.prisma.commissionSettlement.findUnique({
      where: { id: settlementId },
    });
    if (!settlement) throw new NotFoundException('ไม่พบรายการโอนคืนนี้');
    const updated = await this.prisma.commissionSettlement.updateMany({
      where: { id: settlementId, status: SettlementStatus.PENDING },
      data: {
        status: SettlementStatus.REJECTED,
        rejectReason: reason,
        reviewedAt: new Date(),
      },
    });
    if (updated.count !== 1) {
      throw new BadRequestException('รายการนี้ถูกดำเนินการไปแล้ว');
    }
    void this.push.providerWalletNotice(
      settlement.providerId,
      'สลิปโอนค่าบริการยังไม่ผ่าน',
      reason,
    );
    return { status: SettlementStatus.REJECTED };
  }

  /** ยอดค่าบริการที่ช่างทุกคนค้างรวมกัน (สตางค์) ใช้ในหน้าสรุปของแอดมิน */
  async totalOutstandingDebt(): Promise<number> {
    const rows = await this.prisma.walletEntry.groupBy({
      by: ['providerId'],
      _sum: { amount: true },
    });
    return rows.reduce(
      (sum, row) => sum + Math.max(0, -(row._sum.amount ?? 0)),
      0,
    );
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
  async creditOrderEarning(
    orderId: string,
    tx?: Prisma.TransactionClient,
  ): Promise<void> {
    const db = tx ?? this.prisma;
    const order = await db.order.findUnique({
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

    await db.walletEntry.createMany({
      data: {
        idempotencyKey: `order-earning:${orderId}`,
        providerId,
        type: WalletEntryType.ORDER_EARNING,
        amount: net,
        orderId,
        memo: `รายได้งาน ${order.orderNo}`,
      },
      skipDuplicates: true,
    });
  }

  /**
   * งานที่ลูกค้าจ่ายเงินสดให้ช่าง: ช่างถือเงินเต็มจำนวนอยู่แล้ว
   * จึงบันทึกค่าธรรมเนียมที่ช่างต้องคืนบริษัทเป็นยอดติดลบ (หักจากรายได้งานพร้อมเพย์ครั้งถัดไป)
   * ห้ามเครดิตรายได้ให้ซ้ำ ไม่งั้นช่างจะเบิกเงินที่บริษัทไม่เคยได้รับ
   */
  async chargeCashCommission(
    orderId: string,
    tx?: Prisma.TransactionClient,
  ): Promise<void> {
    const db = tx ?? this.prisma;
    const order = await db.order.findUnique({
      where: { id: orderId },
    });
    if (!order) throw new NotFoundException('ไม่พบออเดอร์นี้');
    if (!order.providerId) {
      throw new BadRequestException('ออเดอร์นี้ไม่มีช่างรับผิดชอบ');
    }
    const gross = order.priceFinal ?? order.priceEstimated;
    const commission = Math.round(gross * order.commissionRate);
    await db.walletEntry.createMany({
      data: {
        idempotencyKey: `cash-commission:${orderId}`,
        providerId: order.providerId,
        type: WalletEntryType.COMMISSION_DUE,
        amount: -commission,
        orderId,
        memo: `ค่าบริการแพลตฟอร์ม งาน ${order.orderNo} (ลูกค้าจ่ายเงินสดกับช่าง)`,
      },
      skipDuplicates: true,
    });
    if (!tx) await this.pauseIfOverDebtLimit(order.providerId);
  }

  /** ค้างเกินเพดานหลังงานเงินสด: ปิดรับงานทันทีและแจ้งช่างให้โอนคืน */
  async pauseIfOverDebtLimit(providerId: string): Promise<void> {
    const debt = await this.getDebtStatus(providerId);
    if (!debt.blocked) return;
    await this.prisma.provider.update({
      where: { id: providerId },
      data: { isOnline: false },
    });
    void this.push.providerWalletNotice(
      providerId,
      'ปิดรับงานชั่วคราว: ค้างค่าบริการเกินเพดาน',
      `ค้างค่าบริการแพลตฟอร์ม ${formatBaht(debt.owed)} โอนชำระในหน้ากระเป๋าเงินแล้วเปิดรับงานต่อได้`,
    );
  }

  /**
   * ช่างกดขอเบิกเงิน — กันยอดออกจากกระเป๋าทันทีเพื่อไม่ให้เบิกซ้อนเกินยอดคงเหลือ
   * ใช้ Serializable กันกรณีกดเบิกพร้อมกันหลายครั้ง
   */
  async requestWithdrawal(providerId: string, amount: number) {
    if (amount <= 0) {
      throw new BadRequestException('จำนวนเงินที่ขอเบิกต้องมากกว่า 0');
    }

    const withdrawal = await serializable(this.prisma, async (tx) => {
      const provider = await tx.provider.findUnique({
        where: { id: providerId },
      });
      if (!provider) throw new NotFoundException('ไม่พบข้อมูลช่าง');

      const hasPayoutInfo =
        Boolean(provider.promptPayId) ||
        Boolean(provider.bankAccountNumber && provider.bankName);
      if (!hasPayoutInfo) {
        throw new BadRequestException('กรุณากรอกข้อมูลบัญชีรับเงินก่อนขอเบิก');
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
    });
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

    const changed = await this.prisma.withdrawalRequest.updateMany({
      where: { id: withdrawalId, status: WithdrawalStatus.REQUESTED },
      data: {
        status: WithdrawalStatus.TRANSFERRED,
        transferredAt: new Date(),
        transferSlip: slipUrl,
        adminNote: note,
      },
    });
    if (changed.count !== 1)
      throw new BadRequestException('คำขอนี้ถูกดำเนินการไปแล้ว');
    return this.prisma.withdrawalRequest.findUniqueOrThrow({
      where: { id: withdrawalId },
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

      const changed = await tx.withdrawalRequest.updateMany({
        where: { id: withdrawalId, status: WithdrawalStatus.REQUESTED },
        data: { status: WithdrawalStatus.REJECTED, adminNote: note },
      });
      if (changed.count !== 1)
        throw new BadRequestException('คำขอนี้ถูกดำเนินการไปแล้ว');

      await tx.walletEntry.create({
        data: {
          providerId: withdrawal.providerId,
          type: WalletEntryType.ADJUSTMENT,
          idempotencyKey: `withdrawal-refund:${withdrawalId}`,
          amount: withdrawal.amount,
          withdrawalId: withdrawal.id,
          memo: 'คืนยอดจากคำขอเบิกที่ถูกปฏิเสธ',
        },
      });

      return tx.withdrawalRequest.findUniqueOrThrow({
        where: { id: withdrawalId },
      });
    });
  }
}
