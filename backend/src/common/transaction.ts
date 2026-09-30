import { ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/** Retry only rolled-back database conflicts; never put network calls in this callback. */
export async function serializable<T>(
  prisma: PrismaService,
  operation: (tx: Prisma.TransactionClient) => Promise<T>,
): Promise<T> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await prisma.$transaction(operation, {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      });
    } catch (error) {
      if (
        !(error instanceof Prisma.PrismaClientKnownRequestError) ||
        error.code !== 'P2034'
      ) {
        throw error;
      }
      if (attempt === 2) {
        throw new ConflictException('มีการทำรายการพร้อมกัน กรุณาลองใหม่');
      }
    }
  }
  throw new ConflictException();
}
