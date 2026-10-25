-- Sign in with Apple: userId ของ Apple ต่อบัญชี และ refresh token ไว้ revoke ตอนลบบัญชี
ALTER TABLE "Customer" ADD COLUMN "appleUserId" TEXT;
ALTER TABLE "Provider" ADD COLUMN "appleUserId" TEXT;

CREATE UNIQUE INDEX "Customer_appleUserId_key" ON "Customer"("appleUserId");
CREATE UNIQUE INDEX "Provider_appleUserId_key" ON "Provider"("appleUserId");

CREATE TABLE "AppleToken" (
    "appleUserId" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "refreshToken" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AppleToken_pkey" PRIMARY KEY ("appleUserId")
);
