import { BadRequestException } from '@nestjs/common';

import {
  FinanceOrderInput,
  FinanceProviderInput,
  FinanceService,
  summarizeFinance,
} from './finance.service';

function order(
  id: string,
  providerId: string | null,
  gross: number,
  payment: FinanceOrderInput['payment'],
): FinanceOrderInput {
  return {
    id,
    orderNo: `FG-${id}`,
    completedAt: new Date('2026-09-10T03:00:00Z'),
    priceFinal: gross,
    priceEstimated: gross,
    commissionRate: 0.35,
    serviceName: 'จั๊มแบต',
    customerPhone: '0811111111',
    customerName: null,
    providerId,
    payment,
  };
}

const provider = (
  id: string,
  balance: number,
  pendingWithdrawal = 0,
): FinanceProviderInput => ({
  id,
  nickname: id,
  realName: `ช่าง ${id}`,
  phone: '0900000000',
  status: 'VERIFIED',
  balance,
  pendingWithdrawal,
});

describe('summarizeFinance', () => {
  const orders = [
    order('1', 'a', 100_000, { status: 'PAID', method: 'PROMPTPAY' }),
    order('2', 'a', 60_000, { status: 'PAID', method: 'CASH' }),
    order('3', 'b', 200_000, { status: 'PAID', method: 'PROMPTPAY' }),
    order('4', 'b', 50_000, { status: 'PENDING', method: 'PROMPTPAY' }),
  ];
  const report = summarizeFinance(orders, [
    provider('a', -21_000),
    provider('b', 150_000, 45_000),
    provider('c', 0),
  ]);

  it('splits money received by PromptPay and cash held by mechanics', () => {
    expect(report.totals).toMatchObject({
      completedJobs: 4,
      grossPaid: 360_000,
      promptPayReceived: 300_000,
      promptPayJobs: 2,
      cashCollectedByMechanics: 60_000,
      cashJobs: 1,
      unpaidAmount: 50_000,
      unpaidJobs: 1,
      commissionEarned: 35_000 + 21_000 + 70_000,
      commissionFromCash: 21_000,
      mechanicShareFromPromptPay: 65_000 + 130_000,
    });
  });

  it('lists every mechanic with their jobs by payment method', () => {
    const a = report.mechanics.find((m) => m.id === 'a')!;
    expect(a).toMatchObject({
      jobs: 2,
      promptPayJobs: 1,
      promptPayGross: 100_000,
      cashJobs: 1,
      cashGross: 60_000,
      commission: 56_000,
      balance: -21_000,
    });
    const c = report.mechanics.find((m) => m.id === 'c')!;
    expect(c.jobs).toBe(0);
    // ช่างที่ทำยอดมากสุดขึ้นก่อน
    expect(report.mechanics.map((m) => m.id)).toEqual(['b', 'a', 'c']);
  });

  it('shows what the company owes mechanics and what mechanics owe back', () => {
    expect(report.position).toEqual({
      owedToMechanics: 150_000 + 45_000,
      owedByMechanics: 21_000,
      pendingWithdrawals: 45_000,
    });
  });

  it('marks unpaid jobs without counting them as revenue', () => {
    const unpaid = report.orders.find((row) => row.id === '4')!;
    expect(unpaid.method).toBe('UNPAID');
  });
});

describe('FinanceService.resolveRange', () => {
  it('defaults to the current month in Thai time', () => {
    // 30 ก.ย. 20:00 UTC = 1 ต.ค. 03:00 เวลาไทย
    const range = FinanceService.resolveRange(
      undefined,
      undefined,
      new Date('2026-09-30T20:00:00Z'),
    );
    expect(range.from).toBe('2026-10-01');
    expect(range.to).toBe('2026-10-01');
    expect(range.start.toISOString()).toBe('2026-09-30T17:00:00.000Z');
    expect(range.end.toISOString()).toBe('2026-10-01T17:00:00.000Z');
  });

  it('rejects bad or reversed dates', () => {
    expect(() => FinanceService.resolveRange('2026/09/01')).toThrow(
      BadRequestException,
    );
    expect(() =>
      FinanceService.resolveRange('2026-09-10', '2026-09-01'),
    ).toThrow(BadRequestException);
    expect(() =>
      FinanceService.resolveRange('2024-01-01', '2026-01-01'),
    ).toThrow(BadRequestException);
  });
});
