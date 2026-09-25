-- AlterEnum
ALTER TYPE "WalletEntryType" ADD VALUE 'COMMISSION_DUE';

-- AlterTable
ALTER TABLE "Payment" ADD COLUMN     "slipRejectReason" TEXT,
ADD COLUMN     "slipSubmittedAt" TIMESTAMP(3),
ADD COLUMN     "slipUrl" TEXT;
