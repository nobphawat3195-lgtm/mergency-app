-- CreateTable
CREATE TABLE "InspectionPhoto" (
    "id" TEXT NOT NULL,
    "reportId" TEXT NOT NULL,
    "slotCode" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "caption" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InspectionPhoto_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "InspectionPhoto_reportId_slotCode_idx" ON "InspectionPhoto"("reportId", "slotCode");

-- AddForeignKey
ALTER TABLE "InspectionPhoto" ADD CONSTRAINT "InspectionPhoto_reportId_fkey" FOREIGN KEY ("reportId") REFERENCES "InspectionReport"("id") ON DELETE CASCADE ON UPDATE CASCADE;
