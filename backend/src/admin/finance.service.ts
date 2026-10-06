import { BadRequestException, Injectable } from '@nestjs/common';
import {
  OrderStatus,
  PaymentMethod,
  PaymentStatus,
  WithdrawalStatus,
} from '@prisma/client';

import { PrismaService } from '../prisma/prisma.service';

/** วันที่ในรายงานเป็นเวลาไทย (UTC+7) */
const BANGKOK_OFFSET = '+07:00';
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_RANGE_DAYS = 366;

export interface FinanceOrderInput {
  id: string;
  orderNo: string;
  completedAt: Date | null;
  priceFinal: number | null;
  priceEstimated: number;
  commissionRate: number;
  serviceName: string;
  customerPhone: string | null;
  customerName: string | null;
  providerId: string | null;
  payment: { status: PaymentStatus; method: PaymentMethod } | null;
}

export interface FinanceProviderInput {
  id: string;
  nickname: string;
  realName: string;
  phone: string;
  status: string;
  /** ยอดกระเป๋าปัจจุบัน (สตางค์) บวก = บริษัทต้องจ่ายช่าง ลบ = ช่างค้างบริษัท */
  balance: number;
  /** คำขอเบิกที่รอโอน (สตางค์) */
  pendingWithdrawal: number;
  /** เวลารับงานที่ช่างตั้งเอง (นาทีนับจากเที่ยงคืน) ให้แอดมินเห็นว่าทำไมช่างไม่ได้งาน */
  openMinute?: number;
  closeMinute?: number;
  isOnline?: boolean;
}

/** วิธีรับเงินของงาน: PAID แล้วใช้ method จริง ยังไม่จ่ายเป็น UNPAID */
export type FinanceMethod = 'PROMPTPAY' | 'CASH' | 'UNPAID';

function methodOf(order: FinanceOrderInput): FinanceMethod {
  if (order.payment?.status !== PaymentStatus.PAID) return 'UNPAID';
  return order.payment.method === PaymentMethod.CASH ? 'CASH' : 'PROMPTPAY';
}

/**
 * สรุปการเงินจากงานที่ปิดแล้วในช่วงเวลา (คำนวณล้วน ไม่แตะฐานข้อมูล ทดสอบได้ตรงๆ)
 *
 * - PROMPTPAY: ลูกค้าโอนเข้าบัญชีบริษัทเต็มจำนวน บริษัทเก็บค่าคอม ส่วนของช่างเข้ากระเป๋ารอเบิก
 * - CASH: ช่างรับเงินเต็มจำนวน ค่าคอมเป็นยอดที่ช่างต้องโอนคืนบริษัท
 * - UNPAID: ปิดงานแล้วแต่ยังไม่ยืนยันการชำระ ยังไม่นับเป็นรายได้
 */
export function summarizeFinance(
  orders: FinanceOrderInput[],
  providers: FinanceProviderInput[],
) {
  const totals = {
    completedJobs: orders.length,
    grossPaid: 0,
    promptPayReceived: 0,
    promptPayJobs: 0,
    cashCollectedByMechanics: 0,
    cashJobs: 0,
    unpaidAmount: 0,
    unpaidJobs: 0,
    /** รายได้บริษัท = ค่าคอมจากงานที่ชำระแล้วทุกวิธี */
    commissionEarned: 0,
    /** ส่วนของค่าคอมที่อยู่กับช่าง (งานเงินสด) ต้องให้ช่างโอนคืน */
    commissionFromCash: 0,
    /** ส่วนของช่างจากงานพร้อมเพย์ (อยู่ในบัญชีบริษัท รอช่างเบิก) */
    mechanicShareFromPromptPay: 0,
  };

  const perProvider = new Map<
    string,
    {
      jobs: number;
      promptPayJobs: number;
      promptPayGross: number;
      cashJobs: number;
      cashGross: number;
      unpaidJobs: number;
      commission: number;
      mechanicNet: number;
    }
  >();

  const rows = orders.map((order) => {
    const gross = order.priceFinal ?? order.priceEstimated;
    const commission = Math.round(gross * order.commissionRate);
    const method = methodOf(order);
    const stats = order.providerId
      ? (perProvider.get(order.providerId) ?? {
          jobs: 0,
          promptPayJobs: 0,
          promptPayGross: 0,
          cashJobs: 0,
          cashGross: 0,
          unpaidJobs: 0,
          commission: 0,
          mechanicNet: 0,
        })
      : null;
    if (stats) stats.jobs += 1;

    if (method === 'UNPAID') {
      totals.unpaidAmount += gross;
      totals.unpaidJobs += 1;
      if (stats) stats.unpaidJobs += 1;
    } else {
      totals.grossPaid += gross;
      totals.commissionEarned += commission;
      if (method === 'PROMPTPAY') {
        totals.promptPayReceived += gross;
        totals.promptPayJobs += 1;
        totals.mechanicShareFromPromptPay += gross - commission;
      } else {
        totals.cashCollectedByMechanics += gross;
        totals.cashJobs += 1;
        totals.commissionFromCash += commission;
      }
      if (stats) {
        stats.commission += commission;
        stats.mechanicNet += gross - commission;
        if (method === 'PROMPTPAY') {
          stats.promptPayJobs += 1;
          stats.promptPayGross += gross;
        } else {
          stats.cashJobs += 1;
          stats.cashGross += gross;
        }
      }
    }
    if (stats && order.providerId) perProvider.set(order.providerId, stats);

    return {
      id: order.id,
      orderNo: order.orderNo,
      completedAt: order.completedAt,
      serviceName: order.serviceName,
      customer: order.customerPhone ?? order.customerName ?? null,
      providerId: order.providerId,
      gross,
      commission,
      mechanicNet: gross - commission,
      method,
    };
  });

  const mechanics = providers.map((provider) => {
    const stats = perProvider.get(provider.id);
    return {
      id: provider.id,
      nickname: provider.nickname,
      realName: provider.realName,
      phone: provider.phone,
      status: provider.status,
      jobs: stats?.jobs ?? 0,
      promptPayJobs: stats?.promptPayJobs ?? 0,
      promptPayGross: stats?.promptPayGross ?? 0,
      cashJobs: stats?.cashJobs ?? 0,
      cashGross: stats?.cashGross ?? 0,
      unpaidJobs: stats?.unpaidJobs ?? 0,
      commission: stats?.commission ?? 0,
      mechanicNet: stats?.mechanicNet ?? 0,
      balance: provider.balance,
      pendingWithdrawal: provider.pendingWithdrawal,
      openMinute: provider.openMinute,
      closeMinute: provider.closeMinute,
      isOnline: provider.isOnline,
    };
  });
  // ช่างที่มีงานในช่วงนี้ขึ้นก่อน เรียงตามยอดงาน
  mechanics.sort(
    (a, b) =>
      b.promptPayGross + b.cashGross - (a.promptPayGross + a.cashGross) ||
      b.jobs - a.jobs,
  );

  const position = {
    /** เงินของช่างที่ค้างอยู่ในบัญชีบริษัท (ยอดกระเป๋าที่เป็นบวก รวมที่รอโอน) ต้องสำรองไว้ */
    owedToMechanics:
      providers.reduce((sum, p) => sum + Math.max(0, p.balance), 0) +
      providers.reduce((sum, p) => sum + p.pendingWithdrawal, 0),
    /** ค่าคอมที่ช่างค้างบริษัทจากงานเงินสด */
    owedByMechanics: providers.reduce(
      (sum, p) => sum + Math.max(0, -p.balance),
      0,
    ),
    pendingWithdrawals: providers.reduce(
      (sum, p) => sum + p.pendingWithdrawal,
      0,
    ),
  };

  return { totals, position, mechanics, orders: rows };
}

@Injectable()
export class FinanceService {
  constructor(private readonly prisma: PrismaService) {}

  /** ช่วงวันที่เวลาไทย ค่าเริ่มต้น = ตั้งแต่วันที่ 1 ของเดือนนี้ถึงวันนี้ */
  static resolveRange(from?: string, to?: string, now: Date = new Date()) {
    const today = new Date(now.getTime() + 7 * 60 * 60_000)
      .toISOString()
      .slice(0, 10);
    const fromDate = from ?? `${today.slice(0, 7)}-01`;
    const toDate = to ?? today;
    if (!DATE.test(fromDate) || !DATE.test(toDate)) {
      throw new BadRequestException('รูปแบบวันที่ต้องเป็น YYYY-MM-DD');
    }
    const start = new Date(`${fromDate}T00:00:00${BANGKOK_OFFSET}`);
    const end = new Date(`${toDate}T00:00:00${BANGKOK_OFFSET}`);
    end.setUTCDate(end.getUTCDate() + 1);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
      throw new BadRequestException('วันที่ไม่ถูกต้อง');
    }
    if (end <= start) {
      throw new BadRequestException('วันเริ่มต้องไม่เกินวันสิ้นสุด');
    }
    if (end.getTime() - start.getTime() > MAX_RANGE_DAYS * 86_400_000) {
      throw new BadRequestException('เลือกช่วงได้ไม่เกิน 1 ปี');
    }
    return { from: fromDate, to: toDate, start, end };
  }

  async report(from?: string, to?: string) {
    const range = FinanceService.resolveRange(from, to);
    const [orders, providers, balances, withdrawals] = await Promise.all([
      this.prisma.order.findMany({
        where: {
          status: OrderStatus.COMPLETED,
          completedAt: { gte: range.start, lt: range.end },
        },
        select: {
          id: true,
          orderNo: true,
          completedAt: true,
          priceFinal: true,
          priceEstimated: true,
          commissionRate: true,
          providerId: true,
          subService: { select: { name: true } },
          customer: { select: { phone: true, name: true } },
          payment: { select: { status: true, method: true } },
        },
        orderBy: { completedAt: 'desc' },
      }),
      this.prisma.provider.findMany({
        select: {
          id: true,
          nickname: true,
          realName: true,
          phone: true,
          status: true,
          openMinute: true,
          closeMinute: true,
          isOnline: true,
        },
      }),
      this.prisma.walletEntry.groupBy({
        by: ['providerId'],
        _sum: { amount: true },
      }),
      this.prisma.withdrawalRequest.groupBy({
        by: ['providerId'],
        where: { status: WithdrawalStatus.REQUESTED },
        _sum: { amount: true },
      }),
    ]);

    const balanceOf = new Map(
      balances.map((row) => [row.providerId, row._sum.amount ?? 0]),
    );
    const pendingOf = new Map(
      withdrawals.map((row) => [row.providerId, row._sum.amount ?? 0]),
    );
    const summary = summarizeFinance(
      orders.map((order) => ({
        id: order.id,
        orderNo: order.orderNo,
        completedAt: order.completedAt,
        priceFinal: order.priceFinal,
        priceEstimated: order.priceEstimated,
        commissionRate: order.commissionRate,
        serviceName: order.subService.name,
        customerPhone: order.customer.phone,
        customerName: order.customer.name,
        providerId: order.providerId,
        payment: order.payment,
      })),
      providers.map((provider) => ({
        ...provider,
        balance: balanceOf.get(provider.id) ?? 0,
        pendingWithdrawal: pendingOf.get(provider.id) ?? 0,
      })),
    );
    return { range: { from: range.from, to: range.to }, ...summary };
  }
}
