-- CreateEnum
CREATE TYPE "InspectionItemStatus" AS ENUM ('PASS', 'ATTENTION', 'FAIL', 'NOT_APPLICABLE');

-- CreateEnum
CREATE TYPE "InspectionVerdict" AS ENUM ('RECOMMENDED', 'CAUTION', 'NOT_RECOMMENDED');

-- CreateTable
CREATE TABLE "InspectionReport" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "checklistVersion" INTEGER NOT NULL,
    "listingUrl" TEXT,
    "sellerName" TEXT,
    "sellerPhone" TEXT,
    "appointmentAt" TIMESTAMP(3),
    "brand" TEXT,
    "model" TEXT,
    "year" INTEGER,
    "color" TEXT,
    "plateNo" TEXT,
    "plateProvince" TEXT,
    "vin" TEXT,
    "engineNo" TEXT,
    "mileageKm" INTEGER,
    "powertrain" TEXT,
    "transmission" TEXT,
    "score" INTEGER,
    "grade" TEXT,
    "verdict" "InspectionVerdict",
    "floodSuspected" BOOLEAN NOT NULL DEFAULT false,
    "accidentSuspected" BOOLEAN NOT NULL DEFAULT false,
    "odometerSuspected" BOOLEAN NOT NULL DEFAULT false,
    "legalIssue" BOOLEAN NOT NULL DEFAULT false,
    "summary" TEXT,
    "submittedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InspectionReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InspectionItemResult" (
    "id" TEXT NOT NULL,
    "reportId" TEXT NOT NULL,
    "itemCode" TEXT NOT NULL,
    "status" "InspectionItemStatus",
    "measurement" DOUBLE PRECISION,
    "note" TEXT,
    "photoUrls" TEXT[],
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InspectionItemResult_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "InspectionReport_orderId_key" ON "InspectionReport"("orderId");

-- CreateIndex
CREATE UNIQUE INDEX "InspectionItemResult_reportId_itemCode_key" ON "InspectionItemResult"("reportId", "itemCode");

-- AddForeignKey
ALTER TABLE "InspectionReport" ADD CONSTRAINT "InspectionReport_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InspectionItemResult" ADD CONSTRAINT "InspectionItemResult_reportId_fkey" FOREIGN KEY ("reportId") REFERENCES "InspectionReport"("id") ON DELETE CASCADE ON UPDATE CASCADE;

