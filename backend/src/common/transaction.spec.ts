import { ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { serializable } from './transaction';

const collision = () =>
  new Prisma.PrismaClientKnownRequestError('conflict', {
    code: 'P2034',
    clientVersion: '5.22.0',
  });

describe('serializable retry', () => {
  it('retries rolled-back database conflicts', async () => {
    const prisma = {
      $transaction: jest
        .fn()
        .mockRejectedValueOnce(collision())
        .mockResolvedValue('done'),
    };
    expect(await serializable(prisma as never, async () => 'done')).toBe(
      'done',
    );
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });
  it('does not retry arbitrary failures', async () => {
    const prisma = {
      $transaction: jest.fn().mockRejectedValue(new Error('database offline')),
    };
    await expect(
      serializable(prisma as never, async () => 'done'),
    ).rejects.toThrow('database offline');
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });
  it('returns a retryable conflict after three collisions', async () => {
    const prisma = { $transaction: jest.fn().mockRejectedValue(collision()) };
    await expect(
      serializable(prisma as never, async () => 'done'),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.$transaction).toHaveBeenCalledTimes(3);
  });
});
