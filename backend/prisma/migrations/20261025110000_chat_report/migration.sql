-- รายงานแชทไม่เหมาะสมจากลูกค้า/ช่าง (App Store Guideline 1.2)
CREATE TABLE "ChatReport" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "reporter" "ChatSender" NOT NULL,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "ChatReport_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ChatReport_resolvedAt_createdAt_idx" ON "ChatReport"("resolvedAt", "createdAt");
CREATE INDEX "ChatReport_orderId_idx" ON "ChatReport"("orderId");

ALTER TABLE "ChatReport" ADD CONSTRAINT "ChatReport_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
