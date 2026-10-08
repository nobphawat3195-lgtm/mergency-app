import { ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { SERIALIZABLE_ATTEMPTS, serializable } from './transaction';

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
    const waits: number[] = [];
    expect(
      await serializable(
        prisma as never,
        async () => 'done',
        (attempt) => {
          waits.push(attempt);
          return 0;
        },
      ),
    ).toBe('done');
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
    // เว้นช่วงก่อนลองใหม่ ไม่ให้คำขอที่ชนกันชนซ้ำทันที
    expect(waits).toEqual([0]);
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
  it('returns a retryable conflict after repeated collisions', async () => {
    const prisma = { $transaction: jest.fn().mockRejectedValue(collision()) };
    await expect(
      serializable(
        prisma as never,
        async () => 'done',
        () => 0,
      ),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.$transaction).toHaveBeenCalledTimes(SERIALIZABLE_ATTEMPTS);
  });
});
