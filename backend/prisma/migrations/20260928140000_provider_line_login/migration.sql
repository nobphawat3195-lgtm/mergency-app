-- AlterTable
ALTER TABLE "Provider" ADD COLUMN     "lineUserId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Provider_lineUserId_key" ON "Provider"("lineUserId");

