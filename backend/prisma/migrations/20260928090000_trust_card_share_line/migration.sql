-- AlterTable
ALTER TABLE "Customer" ADD COLUMN     "lineUserId" TEXT,
ALTER COLUMN "phone" DROP NOT NULL;

-- AlterTable
ALTER TABLE "Order" ADD COLUMN     "shareToken" TEXT;

-- AlterTable
ALTER TABLE "Provider" ADD COLUMN     "locationAt" TIMESTAMP(3),
ADD COLUMN     "photoUrl" TEXT,
ADD COLUMN     "vehicleDesc" TEXT,
ADD COLUMN     "vehiclePlate" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Customer_lineUserId_key" ON "Customer"("lineUserId");

-- CreateIndex
CREATE UNIQUE INDEX "Order_shareToken_key" ON "Order"("shareToken");

