-- รูปรถหลังซ่อมเสร็จ (บังคับ) และใบเสร็จ (ไม่บังคับ) ที่ช่างแนบตอนปิดงาน
CREATE TYPE "ClosePhotoKind" AS ENUM ('CAR', 'RECEIPT');

CREATE TABLE "OrderClosePhoto" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "kind" "ClosePhotoKind" NOT NULL,
    "url" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OrderClosePhoto_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "OrderClosePhoto_orderId_idx" ON "OrderClosePhoto"("orderId");

ALTER TABLE "OrderClosePhoto" ADD CONSTRAINT "OrderClosePhoto_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
