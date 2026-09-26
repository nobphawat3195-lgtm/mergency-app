-- AlterTable
ALTER TABLE "Customer" ADD COLUMN     "deletedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Provider" ADD COLUMN     "deletedAt" TIMESTAMP(3);
