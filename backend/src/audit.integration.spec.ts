import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import {
  OrderStatus,
  PaymentMethod,
  PaymentStatus,
  ProviderStatus,
  QuoteStatus,
} from '@prisma/client';
import { PrismaService } from './prisma/prisma.service';
import { PaymentsService } from './payments/payments.service';
import { WalletService } from './wallet/wallet.service';
import { OrdersService } from './orders/orders.service';
import { DispatchService } from './dispatch/dispatch.service';
import { CatalogService } from './catalog/catalog.service';
import { InspectionsService } from './inspections/inspections.service';
import { AccountService } from './account/account.service';
import { FinanceService } from './admin/finance.service';
import { ManualPromptPayGateway } from './payments/payment-gateway';
import { allChecklistItems } from './inspections/checklist';
import { isApplicable } from './inspections/grading';
import { PHOTO_SLOTS } from './inspections/photo-slots';

// Never truncate an arbitrary database. This opt-in suite only accepts the named local test DB.
const testUrl = process.env.FIXGO_TEST_DATABASE_URL;
if (testUrl) {
  const parsed = new URL(testUrl);
  if (
    !['localhost', '127.0.0.1'].includes(parsed.hostname) ||
    parsed.pathname !== '/fixgo_audit_test'
  ) {
    throw new Error(
      'Integration tests require a local database named fixgo_audit_test',
    );
  }
}
const integration = testUrl ? describe : describe.skip;

integration('FixGo audit regressions on PostgreSQL', () => {
  const prisma = new PrismaService({
    datasources: {
      db: { url: testUrl ?? 'postgresql://unused@127.0.0.1/fixgo_audit_test' },
    },
  });
  const push = new Proxy(
    {},
    { get: () => jest.fn().mockResolvedValue(undefined) },
  );
  const alerts = new Proxy(
    {},
    { get: () => jest.fn().mockResolvedValue(undefined) },
  );
  const uploads = {
    assertOwnedUploads: jest.fn(),
    deleteUploads: jest.fn().mockResolvedValue(undefined),
  };
  const events = { emit: jest.fn() };
  const wallet = new WalletService(
    prisma,
    alerts as never,
    push as never,
    uploads as never,
  );
  const catalog = new CatalogService(prisma);
  const inspections = new InspectionsService(prisma, uploads as never);
  const dispatch = new DispatchService(
    prisma,
    push as never,
    alerts as never,
    events as never,
    wallet,
  );
  const orders = new OrdersService(
    prisma,
    catalog,
    dispatch,
    inspections,
    push as never,
    uploads as never,
  );
  const payments = new PaymentsService(
    prisma,
    wallet,
    new ManualPromptPayGateway('0812345678', 'Test'),
    push as never,
    alerts as never,
    uploads as never,
  );
  const account = new AccountService(prisma, wallet, uploads as never);
  let customerId: string;
  let providerId: string;
  let categoryId: string;
  let subServiceId: string;
  let vehicleTypeId: string;
  let sequence = 0;

  beforeAll(async () => {
    await prisma.$connect();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    jest.restoreAllMocks();
    await prisma.$executeRawUnsafe(
      'TRUNCATE "Customer", "Provider", "ServiceCategory", "VehicleType", "OtpCode" CASCADE',
    );
    customerId = (
      await prisma.customer.create({ data: { phone: '0800000001' } })
    ).id;
    providerId = (
      await prisma.provider.create({
        data: {
          phone: '0800000002',
          realName: 'Test',
          nickname: 'Test',
          experienceYears: 5,
          baseLat: 13.7,
          baseLng: 100.5,
          openMinute: 0,
          closeMinute: 1439,
          status: ProviderStatus.VERIFIED,
          isOnline: true,
          lastSeenAt: new Date(),
        },
      })
    ).id;
    categoryId = (
      await prisma.serviceCategory.create({
        data: { slug: 'repair', name: 'Repair', iconKey: 'repair' },
      })
    ).id;
    subServiceId = (
      await prisma.subService.create({
        data: {
          categoryId,
          name: 'Repair',
          basePrice: 10000,
          priceType: 'FULL_SERVICE',
        },
      })
    ).id;
    vehicleTypeId = (
      await prisma.vehicleType.create({ data: { slug: 'car', name: 'Car' } })
    ).id;
  });

  async function job(
    status: OrderStatus = OrderStatus.COMPLETED,
    score = 10000,
  ) {
    return prisma.order.create({
      data: {
        orderNo: `TEST-${++sequence}`,
        customerId,
        providerId,
        categoryId,
        subServiceId,
        vehicleTypeId,
        pickupLat: 13.7,
        pickupLng: 100.5,
        priceEstimated: score,
        priceProposed: score,
        priceFinal: status === OrderStatus.COMPLETED ? score : null,
        commissionRate: 0.35,
        status,
        quoteStatus: QuoteStatus.APPROVED,
        ...(status === OrderStatus.COMPLETED
          ? { completedAt: new Date(), payment: { create: { amount: score } } }
          : {}),
      },
      include: { payment: true },
    });
  }
  async function earningJob() {
    const order = await job();
    await payments.markPaidFromGateway({
      paymentId: order.payment!.id,
      chargeId: 'pi-test',
      amountReceived: 10000,
      currency: 'thb',
    });
    return order;
  }

  it('rolls back PAID when ledger insertion fails, then succeeds on retry', async () => {
    const order = await job();
    jest
      .spyOn(wallet, 'creditOrderEarning')
      .mockRejectedValueOnce(new Error('ledger down'));
    const confirmation = {
      paymentId: order.payment!.id,
      chargeId: 'pi-test',
      amountReceived: 10000,
      currency: 'thb',
    };
    await expect(payments.markPaidFromGateway(confirmation)).rejects.toThrow(
      'ledger down',
    );
    expect(
      (await prisma.payment.findUniqueOrThrow({ where: { orderId: order.id } }))
        .status,
    ).toBe(PaymentStatus.PENDING);
    await payments.markPaidFromGateway(confirmation);
    expect(await wallet.getBalance(providerId)).toBe(6500);
  });

  it('commits one ledger entry for concurrent duplicate webhooks', async () => {
    const order = await job();
    const confirmation = {
      paymentId: order.payment!.id,
      chargeId: 'pi-test',
      amountReceived: 10000,
      currency: 'thb',
    };
    await Promise.all(
      Array.from({ length: 5 }, () =>
        payments.markPaidFromGateway(confirmation),
      ),
    );
    expect(
      await prisma.walletEntry.count({ where: { orderId: order.id } }),
    ).toBe(1);
    expect(await wallet.getBalance(providerId)).toBe(6500);
  });

  it('cash and online confirmation cannot both post to the ledger', async () => {
    const order = await job();
    await Promise.allSettled([
      payments.confirmCashPayment(order.id, providerId),
      payments.markPaidFromGateway({
        paymentId: order.payment!.id,
        chargeId: 'pi-test',
        amountReceived: 10000,
        currency: 'thb',
      }),
    ]);
    const paid = await prisma.payment.findUniqueOrThrow({
      where: { orderId: order.id },
    });
    expect(paid.status).toBe(PaymentStatus.PAID);
    expect(
      await prisma.walletEntry.count({ where: { orderId: order.id } }),
    ).toBe(1);
    expect(await wallet.getBalance(providerId)).toBe(
      paid.method === PaymentMethod.CASH ? -3500 : 6500,
    );
  });

  it('rejects a gateway amount mismatch without posting money', async () => {
    const order = await job();
    expect(
      await payments.markPaidFromGateway({
        paymentId: order.payment!.id,
        chargeId: 'pi-test',
        amountReceived: 1,
        currency: 'thb',
      }),
    ).toBe('ignored');
    expect(await wallet.getBalance(providerId)).toBe(0);
  });

  it('manual slip confirmation also rolls back on ledger failure', async () => {
    const order = await job();
    await payments.submitSlip(order.id, customerId, 'https://test/slip.jpg');
    jest
      .spyOn(wallet, 'creditOrderEarning')
      .mockRejectedValueOnce(new Error('ledger down'));
    await expect(payments.confirmSlip(order.payment!.id)).rejects.toThrow(
      'ledger down',
    );
    expect(
      (await prisma.payment.findUniqueOrThrow({ where: { orderId: order.id } }))
        .status,
    ).toBe('PENDING');
    await payments.confirmSlip(order.payment!.id);
    expect(await wallet.getBalance(providerId)).toBe(6500);
  });

  it('does not expose a customer slip to the assigned mechanic', async () => {
    const order = await job();
    await payments.submitSlip(order.id, customerId, 'https://test/slip.jpg');
    expect(
      await payments.getPaymentForActor(order.id, {
        sub: providerId,
        role: 'PROVIDER',
      }),
    ).not.toHaveProperty('slipUrl');
    expect(
      await payments.getPaymentForActor(order.id, {
        sub: customerId,
        role: 'CUSTOMER',
      }),
    ).toHaveProperty('slipUrl');
  });

  async function withdrawal() {
    await earningJob();
    await prisma.provider.update({
      where: { id: providerId },
      data: { promptPayId: '0800000002' },
    });
    return wallet.requestWithdrawal(providerId, 6000);
  }

  it('concurrent rejection refunds a withdrawal only once', async () => {
    const request = await withdrawal();
    const result = await Promise.allSettled([
      wallet.rejectWithdrawal(request.id),
      wallet.rejectWithdrawal(request.id),
    ]);
    expect(result.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(await wallet.getBalance(providerId)).toBe(6500);
    expect(
      await prisma.walletEntry.count({
        where: { withdrawalId: request.id, type: 'ADJUSTMENT' },
      }),
    ).toBe(1);
  });

  it('transfer and reject resolve to a consistent balance and one terminal status', async () => {
    const request = await withdrawal();
    const result = await Promise.allSettled([
      wallet.markTransferred(request.id),
      wallet.rejectWithdrawal(request.id),
    ]);
    expect(result.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    const resolved = await prisma.withdrawalRequest.findUniqueOrThrow({
      where: { id: request.id },
    });
    expect(await wallet.getBalance(providerId)).toBe(
      resolved.status === 'TRANSFERRED' ? 500 : 6500,
    );
  });

  it('cancellation cannot be overwritten by a concurrent journey update', async () => {
    const order = await job(OrderStatus.MATCHED);
    await Promise.allSettled([
      orders.cancelByCustomer(customerId, order.id),
      orders.updateStatusByProvider(providerId, order.id, OrderStatus.EN_ROUTE),
    ]);
    const final = await prisma.order.findUniqueOrThrow({
      where: { id: order.id },
    });
    expect(
      final.cancelledAt === null || final.status === OrderStatus.CANCELLED,
    ).toBe(true);
  });

  it('rejects approval of a stale quote even when the amount is unchanged', async () => {
    const order = await job(OrderStatus.EN_ROUTE);
    await prisma.order.update({
      where: { id: order.id },
      data: { quoteStatus: QuoteStatus.PENDING, quoteVersion: 2 },
    });
    await expect(
      orders.respondToQuote(customerId, order.id, true, {
        quoteVersion: 1,
        priceProposed: 10000,
      }),
    ).rejects.toBeInstanceOf(ConflictException);
    await orders.respondToQuote(customerId, order.id, true, {
      quoteVersion: 2,
      priceProposed: 10000,
    });
  });

  it('cannot overwrite a pending or approved quote', async () => {
    const order = await job(OrderStatus.EN_ROUTE);
    await expect(
      orders.proposeQuote(providerId, order.id, { priceProposed: 20000 }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('suspended mechanics cannot accept an outstanding offer', async () => {
    const order = await job(OrderStatus.SEARCHING);
    await prisma.order.update({
      where: { id: order.id },
      data: { providerId: null },
    });
    await prisma.dispatchAttempt.create({
      data: {
        orderId: order.id,
        providerId,
        rank: 1,
        distanceKm: 1,
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    await prisma.provider.update({
      where: { id: providerId },
      data: { status: ProviderStatus.SUSPENDED },
    });
    await expect(dispatch.accept(order.id, providerId)).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(
      (await prisma.order.findUniqueOrThrow({ where: { id: order.id } }))
        .providerId,
    ).toBeNull();
  });

  it('blocks deletion of a mechanic with outstanding commission debt', async () => {
    const order = await job();
    await payments.confirmCashPayment(order.id, providerId);
    await expect(
      account.deleteAccount(providerId, 'PROVIDER'),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(
      (await prisma.provider.findUniqueOrThrow({ where: { id: providerId } }))
        .deletedAt,
    ).toBeNull();
  });

  it('keeps historical debt of deleted mechanics in the finance position', async () => {
    await prisma.walletEntry.create({
      data: { providerId, type: 'COMMISSION_DUE', amount: -3500 },
    });
    await prisma.provider.update({
      where: { id: providerId },
      data: { deletedAt: new Date() },
    });
    expect(
      (await new FinanceService(prisma).report()).position.owedByMechanics,
    ).toBe(3500);
  });

  it('rejects inactive services, categories and vehicle types', async () => {
    await prisma.subService.update({
      where: { id: subServiceId },
      data: { active: false },
    });
    await expect(catalog.quote(subServiceId, vehicleTypeId)).rejects.toThrow();
    await prisma.subService.update({
      where: { id: subServiceId },
      data: { active: true },
    });
    await prisma.serviceCategory.update({
      where: { id: categoryId },
      data: { active: false },
    });
    await expect(catalog.quote(subServiceId, vehicleTypeId)).rejects.toThrow();
    await prisma.serviceCategory.update({
      where: { id: categoryId },
      data: { active: true },
    });
    await prisma.vehicleType.update({
      where: { id: vehicleTypeId },
      data: { active: false },
    });
    await expect(catalog.quote(subServiceId, vehicleTypeId)).rejects.toThrow();
  });

  it('keeps future appointments unassigned and starts dispatch when due', async () => {
    const order = await job(OrderStatus.CREATED);
    await prisma.order.update({
      where: { id: order.id },
      data: { providerId: null },
    });
    await prisma.inspectionReport.create({
      data: {
        orderId: order.id,
        checklistVersion: 1,
        appointmentAt: new Date(Date.now() + 3 * 3600000),
      },
    });
    await dispatch.startDispatch(order.id);
    expect(
      (await prisma.order.findUniqueOrThrow({ where: { id: order.id } }))
        .status,
    ).toBe(OrderStatus.CREATED);
    await prisma.inspectionReport.update({
      where: { orderId: order.id },
      data: { appointmentAt: new Date(Date.now() + 30 * 60000) },
    });
    await dispatch.expireStaleOffers();
    expect(
      (await prisma.order.findUniqueOrThrow({ where: { id: order.id } }))
        .status,
    ).toBe(OrderStatus.NO_MATCH);
  });

  it('does not restart cancelled orders during dispatch', async () => {
    const order = await job(OrderStatus.CANCELLED);
    await dispatch.startDispatch(order.id);
    expect(
      (await prisma.order.findUniqueOrThrow({ where: { id: order.id } }))
        .status,
    ).toBe(OrderStatus.CANCELLED);
  });

  it('concurrent ratings produce the actual average and count', async () => {
    const a = await job();
    const b = await job();
    await Promise.all([
      orders.rate(customerId, a.id, { score: 1 }),
      orders.rate(customerId, b.id, { score: 5 }),
    ]);
    const provider = await prisma.provider.findUniqueOrThrow({
      where: { id: providerId },
    });
    expect(provider.ratingAvg).toBe(3);
    expect(provider.ratingCount).toBe(2);
  });

  it('duplicate concurrent ratings return a client error and leave one score', async () => {
    const order = await job();
    const results = await Promise.allSettled([
      orders.rate(customerId, order.id, { score: 3 }),
      orders.rate(customerId, order.id, { score: 3 }),
    ]);
    expect(
      results.filter((result) => result.status === 'fulfilled'),
    ).toHaveLength(1);
    const rejected = results.find(
      (result) => result.status === 'rejected',
    ) as PromiseRejectedResult;
    expect(rejected.reason).toBeInstanceOf(BadRequestException);
    expect(
      (await prisma.provider.findUniqueOrThrow({ where: { id: providerId } }))
        .ratingCount,
    ).toBe(1);
  });

  it('does not allow a deleted customer to create an order', async () => {
    await prisma.customer.update({
      where: { id: customerId },
      data: { deletedAt: new Date() },
    });
    await expect(
      orders.create(customerId, {
        categoryId,
        subServiceId,
        vehicleTypeId,
        pickupLat: 13.7,
        pickupLng: 100.5,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('generates unique database sequence numbers for concurrent bookings', async () => {
    const created = await Promise.all(
      Array.from({ length: 5 }, () =>
        orders.create(customerId, {
          categoryId,
          subServiceId,
          vehicleTypeId,
          pickupLat: 13.7,
          pickupLng: 100.5,
        }),
      ),
    );
    expect(new Set(created.map((order) => order.orderNo)).size).toBe(5);
    expect(
      created.every((order) => /^FG\d{6}-\d{8,}$/.test(order.orderNo)),
    ).toBe(true);
  });

  it('validates inspection appointment dates at the server boundary', async () => {
    await prisma.serviceCategory.update({
      where: { id: categoryId },
      data: { slug: 'used-car-inspection' },
    });
    const input = {
      categoryId,
      subServiceId,
      vehicleTypeId,
      pickupLat: 13.7,
      pickupLng: 100.5,
    };
    await expect(
      orders.create(customerId, {
        ...input,
        inspection: {
          appointmentAt: new Date(Date.now() - 3600000).toISOString(),
        },
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    const created = await orders.create(customerId, {
      ...input,
      inspection: {
        appointmentAt: new Date(Date.now() + 3 * 3600000).toISOString(),
      },
    });
    expect(created.status).toBe(OrderStatus.CREATED);
    expect(created.providerId).toBeNull();
  });

  it('cancelling an order closes all outstanding offers', async () => {
    const order = await job(OrderStatus.SEARCHING);
    await prisma.order.update({
      where: { id: order.id },
      data: { providerId: null },
    });
    await prisma.dispatchAttempt.create({
      data: {
        orderId: order.id,
        providerId,
        rank: 1,
        distanceKm: 1,
        expiresAt: new Date(Date.now() + 60000),
      },
    });
    await orders.cancelByCustomer(customerId, order.id);
    expect(await dispatch.listOffersForProvider(providerId)).toHaveLength(0);
    expect(
      (
        await prisma.dispatchAttempt.findFirstOrThrow({
          where: { orderId: order.id },
        })
      ).status,
    ).toBe('EXPIRED');
  });

  it('report submission and concurrent edit always leave a matching grade', async () => {
    const order = await job(OrderStatus.IN_PROGRESS);
    await prisma.serviceCategory.update({
      where: { id: categoryId },
      data: { slug: 'used-car-inspection' },
    });
    const vehicle = {
      powertrain: 'combustion' as const,
      transmission: 'automatic' as const,
    };
    await prisma.inspectionReport.create({
      data: {
        orderId: order.id,
        checklistVersion: 1,
        brand: 'Test',
        model: 'Test',
        year: 2020,
        plateNo: 'TEST',
        vin: 'TEST-VIN',
        mileageKm: 1000,
        ...vehicle,
        items: {
          create: allChecklistItems()
            .filter((item) => isApplicable(item.appliesTo, vehicle))
            .map((item) => ({
              itemCode: item.code,
              status: 'PASS' as const,
              photoUrls: [],
            })),
        },
        photos: {
          create: PHOTO_SLOTS.filter((slot) => slot.required).map((slot) => ({
            slotCode: slot.code,
            url: 'https://test/photo.jpg',
            sortOrder: 0,
          })),
        },
      },
    });
    await Promise.allSettled([
      inspections.submit(order.id, providerId),
      inspections.update(order.id, providerId, {
        items: [
          {
            itemCode: 'FRM01',
            status: 'FAIL',
            photoUrls: ['https://test/defect.jpg'],
          },
        ],
      }),
    ]);
    const report = await prisma.inspectionReport.findUniqueOrThrow({
      where: { orderId: order.id },
      include: { items: true },
    });
    if (report.submittedAt) {
      const frame = report.items.find((item) => item.itemCode === 'FRM01')!;
      expect(report.verdict).toBe(
        frame.status === 'FAIL' ? 'NOT_RECOMMENDED' : 'RECOMMENDED',
      );
      await expect(
        inspections.update(order.id, providerId, { summary: 'changed' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    } else {
      await inspections.submit(order.id, providerId);
    }
  });
});
