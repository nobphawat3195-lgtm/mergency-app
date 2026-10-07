import { ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/** ลองใหม่ได้กี่ครั้งเมื่อฐานข้อมูลยกเลิกธุรกรรมเพราะชนกัน */
export const SERIALIZABLE_ATTEMPTS = 5;

/** Retry only rolled-back database conflicts; never put network calls in this callback. */
export async function serializable<T>(
  prisma: PrismaService,
  operation: (tx: Prisma.TransactionClient) => Promise<T>,
  backoffMs: (attempt: number) => number = jitteredBackoff,
): Promise<T> {
  for (let attempt = 0; attempt < SERIALIZABLE_ATTEMPTS; attempt++) {
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
      if (attempt === SERIALIZABLE_ATTEMPTS - 1) {
        throw new ConflictException('มีการทำรายการพร้อมกัน กรุณาลองใหม่');
      }
      // คำขอที่ชนกันแล้วลองใหม่ทันทีพร้อมกันจะชนซ้ำอีก: เว้นช่วงแบบสุ่มให้เหลื่อมกัน
      await new Promise((resolve) => setTimeout(resolve, backoffMs(attempt)));
    }
  }
  throw new ConflictException();
}

/** รอ 5-25 ms คูณจำนวนครั้งที่ชน (สุ่มให้แต่ละคำขอไม่ตื่นพร้อมกัน) */
function jitteredBackoff(attempt: number): number {
  return (attempt + 1) * (5 + Math.random() * 20);
}
