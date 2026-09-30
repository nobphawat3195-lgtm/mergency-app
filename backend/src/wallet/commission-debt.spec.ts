import { BadRequestException, ForbiddenException } from '@nestjs/common';

import { cashDebtLimit } from '../common/constants';
import { WalletService } from './wallet.service';

describe('cashDebtLimit', () => {
  it('defaults to 1,000 baht and reads CASH_DEBT_LIMIT_BAHT', () => {
    expect(cashDebtLimit({})).toBe(100_000);
    expect(cashDebtLimit({ CASH_DEBT_LIMIT_BAHT: '1500' })).toBe(150_000);
    expect(() => cashDebtLimit({ CASH_DEBT_LIMIT_BAHT: '-5' })).toThrow();
  });
});

describe('WalletService commission debt', () => {
  const saved = { ...process.env };
  let balance: number;
  let latestSettlement: Record<string, unknown> | null;
  let prisma: Record<string, Record<string, jest.Mock>> & {
    $transaction: jest.Mock;
  };
  let push: { providerWalletNotice: jest.Mock };
  let service: WalletService;

  beforeEach(() => {
    process.env.CASH_DEBT_LIMIT_BAHT = '1000';
    process.env.PROMPTPAY_ID = '0812345678';
    process.env.PROMPTPAY_NAME = 'FixGo';
    balance = 0;
    latestSettlement = null;
    const aggregate = jest.fn(async () => ({ _sum: { amount: balance } }));
    prisma = {
      walletEntry: {
        aggregate,
        createMany: jest.fn().mockResolvedValue({ count: 1 }),
        create: jest.fn().mockResolvedValue({}),
      },
      commissionSettlement: {
        findFirst: jest.fn(async () => latestSettlement),
        findUnique: jest.fn(async () => latestSettlement),
        create: jest.fn(async ({ data }) => ({ id: 's1', ...data })),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      provider: {
        findUniqueOrThrow: jest.fn().mockResolvedValue({ nickname: 'ชาย' }),
        update: jest.fn().mockResolvedValue({}),
      },
      order: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'o1',
          orderNo: 'FG-1',
          providerId: 'p1',
          priceFinal: 400_000,
          priceEstimated: 400_000,
          commissionRate: 0.35,
        }),
      },
      $transaction: jest.fn(),
    } as never;
    prisma.$transaction.mockImplementation(
      async (fn: (tx: unknown) => unknown) => fn(prisma),
    );
    push = { providerWalletNotice: jest.fn().mockResolvedValue(undefined) };
    service = new WalletService(
      prisma as never,
      { settlementSubmitted: jest.fn() } as never,
      push as never,
      { assertOwnedUploads: jest.fn() } as never,
    );
  });

  afterEach(() => {
    process.env = { ...saved };
  });

  it('lets a mechanic work while the debt is within the limit', async () => {
    balance = -100_000;
    await expect(service.assertCanTakeJobs('p1')).resolves.toBeUndefined();
    expect((await service.getDebtStatus('p1')).blocked).toBe(false);
  });

  it('blocks taking jobs once the debt passes the limit', async () => {
    balance = -100_001;
    const debt = await service.getDebtStatus('p1');
    expect(debt).toMatchObject({
      owed: 100_001,
      limit: 100_000,
      blocked: true,
    });
    await expect(service.assertCanTakeJobs('p1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('switches the mechanic offline when a cash job pushes the debt over the limit', async () => {
    balance = -140_000;
    await service.chargeCashCommission('o1');
    expect(prisma.walletEntry.createMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ amount: -140_000 }),
      }),
    );
    expect(prisma.provider.update).toHaveBeenCalledWith({
      where: { id: 'p1' },
      data: { isOnline: false },
    });
    expect(push.providerWalletNotice).toHaveBeenCalled();
  });

  it('leaves the mechanic online while still under the limit', async () => {
    balance = -50_000;
    await service.chargeCashCommission('o1');
    expect(prisma.provider.update).not.toHaveBeenCalled();
  });

  it('builds a PromptPay QR locked to the full amount owed', async () => {
    balance = -123_450;
    const qr = await service.settlementQr('p1');
    expect(qr.amount).toBe(123_450);
    expect(qr.qrPayload).toContain('54071234.50');
  });

  it('records a slip for the amount owed, one pending slip at a time', async () => {
    balance = -80_000;
    const settlement = await service.submitSettlement(
      'p1',
      'https://x/slip.jpg',
    );
    expect(settlement).toMatchObject({ amount: 80_000, providerId: 'p1' });

    latestSettlement = { id: 's1', status: 'PENDING' };
    await expect(
      service.submitSettlement('p1', 'https://x/slip2.jpg'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuses a slip when nothing is owed', async () => {
    balance = 5_000;
    await expect(
      service.submitSettlement('p1', 'https://x/slip.jpg'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('credits the wallet once when the admin confirms', async () => {
    latestSettlement = {
      id: 's1',
      providerId: 'p1',
      amount: 80_000,
      status: 'PENDING',
    };
    await service.confirmSettlement('s1');
    expect(prisma.walletEntry.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        idempotencyKey: 'settlement:s1',
        type: 'COMMISSION_PAID',
        amount: 80_000,
      }),
    });

    // กดยืนยันซ้ำพร้อมกัน: updateMany ไม่เจอรายการ PENDING แล้ว ต้องไม่ลงยอดซ้ำ
    prisma.walletEntry.create.mockClear();
    prisma.commissionSettlement.updateMany.mockResolvedValue({ count: 0 });
    await service.confirmSettlement('s1');
    expect(prisma.walletEntry.create).not.toHaveBeenCalled();
  });
});
