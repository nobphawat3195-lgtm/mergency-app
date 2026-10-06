-- แชทระหว่างลูกค้ากับช่างในแต่ละงาน
CREATE TYPE "ChatSender" AS ENUM ('CUSTOMER', 'PROVIDER');

ALTER TABLE "Order" ADD COLUMN "chatCustomerReadAt" TIMESTAMP(3);
ALTER TABLE "Order" ADD COLUMN "chatProviderReadAt" TIMESTAMP(3);

CREATE TABLE "OrderMessage" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "sender" "ChatSender" NOT NULL,
    "text" TEXT,
    "imageUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OrderMessage_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "OrderMessage_orderId_createdAt_idx" ON "OrderMessage"("orderId", "createdAt");

ALTER TABLE "OrderMessage" ADD CONSTRAINT "OrderMessage_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
