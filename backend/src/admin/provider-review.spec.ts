import { BadRequestException } from '@nestjs/common';
import { ProviderStatus } from '@prisma/client';

import { AdminService } from './admin.service';

function setup(current: ProviderStatus = ProviderStatus.PENDING) {
  const prisma = {
    provider: {
      findUnique: jest
        .fn()
        .mockResolvedValue({ id: 'p1', status: current, isOnline: true }),
      update: jest
        .fn()
        .mockImplementation(({ data }) => ({ id: 'p1', ...data })),
    },
  };
  const push = { providerReviewed: jest.fn().mockResolvedValue(undefined) };
  const service = new AdminService(
    prisma as never,
    {} as never,
    {} as never,
    {} as never,
    push as never,
  );
  return { service, prisma, push };
}

describe('AdminService.setProviderStatus', () => {
  it('approves and tells the mechanic', async () => {
    const { service, prisma, push } = setup();
    await service.setProviderStatus('p1', ProviderStatus.VERIFIED);
    expect(prisma.provider.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: ProviderStatus.VERIFIED,
          reviewNote: null,
        }),
      }),
    );
    expect(push.providerReviewed).toHaveBeenCalledWith('p1', true, null);
  });

  it('requires a reason to reject, then takes the mechanic offline', async () => {
    const { service, prisma, push } = setup();
    await expect(
      service.setProviderStatus('p1', ProviderStatus.REJECTED),
    ).rejects.toBeInstanceOf(BadRequestException);

    await service.setProviderStatus(
      'p1',
      ProviderStatus.REJECTED,
      '  รูปเครื่องมือไม่ชัด  ',
    );
    expect(prisma.provider.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: ProviderStatus.REJECTED,
          reviewNote: 'รูปเครื่องมือไม่ชัด',
          isOnline: false,
        }),
      }),
    );
    expect(push.providerReviewed).toHaveBeenCalledWith(
      'p1',
      false,
      'รูปเครื่องมือไม่ชัด',
    );
  });

  it('cannot move a mechanic back to pending', async () => {
    const { service } = setup(ProviderStatus.VERIFIED);
    await expect(
      service.setProviderStatus('p1', ProviderStatus.PENDING),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('does not re-notify when the status is unchanged', async () => {
    const { service, push } = setup(ProviderStatus.VERIFIED);
    await service.setProviderStatus('p1', ProviderStatus.VERIFIED);
    expect(push.providerReviewed).not.toHaveBeenCalled();
  });
});
