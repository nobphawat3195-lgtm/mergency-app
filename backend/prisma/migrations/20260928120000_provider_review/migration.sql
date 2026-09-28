-- AlterEnum
ALTER TYPE "ProviderStatus" ADD VALUE 'REJECTED';

-- AlterTable
ALTER TABLE "Provider" ADD COLUMN     "reviewNote" TEXT,
ADD COLUMN     "reviewedAt" TIMESTAMP(3);

