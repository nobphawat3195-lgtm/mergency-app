-- คำตอบหลังให้ดาว: อยากให้ FixGo เพิ่มบริการหรือปรับอะไร
CREATE TABLE "ServiceSuggestion" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "choices" TEXT[],
    "otherText" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ServiceSuggestion_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ServiceSuggestion_orderId_key" ON "ServiceSuggestion"("orderId");

CREATE INDEX "ServiceSuggestion_createdAt_idx" ON "ServiceSuggestion"("createdAt");

ALTER TABLE "ServiceSuggestion" ADD CONSTRAINT "ServiceSuggestion_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
