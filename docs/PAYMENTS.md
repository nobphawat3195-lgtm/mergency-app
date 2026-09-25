# ระบบรับชำระเงิน

มี 2 โหมดให้เลือกด้วย `PAYMENT_PROVIDER`:

| โหมด | เงินเข้า | ยืนยันยอด | ค่าธรรมเนียม |
|---|---|---|---|
| `promptpay_manual` | พร้อมเพย์ของเจ้าของโดยตรง | แอดมินตรวจสลิปแล้วกดยืนยัน | ไม่มี |
| `stripe` | บัญชี Stripe แล้วโอนเข้าธนาคาร | webhook อัตโนมัติ | ตามอัตรา Stripe |

## โหมดพร้อมเพย์ + ตรวจสลิป (`promptpay_manual`)

ตั้งค่า:
```
PAYMENT_PROVIDER="promptpay_manual"
PROMPTPAY_ID="08xxxxxxxx"      # หรือเลขประจำตัวผู้เสียภาษี 13 หลัก
PROMPTPAY_NAME="ชื่อบัญชี"      # แสดงให้ลูกค้าเทียบกับชื่อในแอปธนาคารก่อนโอน
```

ขั้นตอน:
1. ลูกค้ากด "ชำระเงินผ่านพร้อมเพย์" ระบบสร้าง QR มาตรฐาน EMVCo (Thai QR) พร้อมยอดเงิน สแกนได้ทุกแอปธนาคาร
2. ลูกค้าโอนแล้วแนบรูปสลิปในแอป (`POST /api/payments/orders/:orderId/slip`)
3. ทีมงานได้รับแจ้งเตือน (LINE/webhook) และสลิปขึ้นในหน้าแอดมินส่วน "สลิปพร้อมเพย์รอตรวจ"
4. แอดมินเปิดแอปธนาคารตรวจว่ายอดเข้าจริง แล้วกด:
   - **ยอดเข้าแล้ว**: สถานะเป็น `PAID` และรายได้ช่าง (65%) เข้ากระเป๋า กดซ้ำได้ ไม่เครดิตซ้ำ
   - **ไม่ผ่าน**: ต้องใส่เหตุผล ลูกค้าได้ push และแนบสลิปใหม่ได้

**ห้ามกด "ยอดเข้าแล้ว" จากรูปสลิปอย่างเดียว** สลิปปลอมทำได้ง่าย ต้องเห็นยอดเข้าในบัญชีจริงทุกครั้ง

## เงินสดและค่าคอมมิชชั่น

เมื่อช่างกด "ยืนยันว่าได้รับเงินสดแล้ว" เงินทั้งหมดอยู่กับช่าง ระบบจึงหักค่าคอมมิชชั่น 35% จากกระเป๋าช่าง
(รายการ `COMMISSION_DUE`) แทนการเพิ่มรายได้ ยอดกระเป๋าติดลบได้ และจะหักกลบกับรายได้จากงานพร้อมเพย์ครั้งถัดไป

# Stripe PromptPay (`stripe`)

## หลักการ
- ลูกค้ากด "ชำระเงินผ่านพร้อมเพย์" หลังช่างปิดงาน ระบบสร้าง Stripe PaymentIntent แบบ `promptpay` แล้วส่ง QR ให้แอป
- **การแสดง QR ไม่ใช่การชำระสำเร็จ** สถานะเป็น `PAID` ได้ 2 ทางเท่านั้น
  1. Stripe ส่ง webhook `payment_intent.succeeded` ที่ตรวจลายเซ็นผ่าน และยอดเงินเป็นบาทตรงกับที่ต้องจ่าย
  2. ช่างกด "ยืนยันว่าได้รับเงินสดแล้ว"
- จับคู่ด้วย `metadata.paymentId` ลูกค้าสแกน QR ใบเก่าก็ยังนับถูก (QR ใบเก่าจะถูกยกเลิกเมื่อขอใบใหม่)
- webhook ส่งซ้ำได้ รายได้ช่างเครดิตครั้งเดียว
- แอปลูกค้าตรวจสถานะทุก 4 วินาทีระหว่างเปิด QR และปิดหน้าต่างเองเมื่อยืนยันยอดแล้ว

## ตั้งค่า (โหมดทดสอบ)
1. Stripe Dashboard (บัญชีประเทศไทย) > Developers > API keys เปิด Test mode คัดลอก Secret key `sk_test_...`
2. Developers > Webhooks > Add endpoint
   - URL: `https://<api-domain>/api/payments/stripe/webhook`
   - Events: `payment_intent.succeeded`
   - คัดลอก Signing secret `whsec_...`
3. ตั้ง env ของ backend
   ```
   PAYMENT_PROVIDER="stripe"
   STRIPE_SECRET_KEY="sk_test_..."
   STRIPE_WEBHOOK_SECRET="whsec_..."
   STRIPE_BILLING_EMAIL="payments@<your-domain>"   # Stripe บังคับอีเมลสำหรับพร้อมเพย์
   ```
4. เซิร์ฟเวอร์ต้องออกเน็ตไปที่ `api.stripe.com` ได้

ทดสอบบนเครื่องตัวเองโดยไม่มีโดเมน: ใช้ Stripe CLI
```
stripe listen --forward-to localhost:3000/api/payments/stripe/webhook
```
CLI จะแสดง `whsec_...` ให้ใส่ใน `STRIPE_WEBHOOK_SECRET`

จำลองการจ่ายในโหมดทดสอบ: เปิด `hostedUrl` ที่ API `POST /api/payments/orders/:id/promptpay` คืนมา
แล้วกดยืนยันการจ่ายในหน้าทดสอบของ Stripe จากนั้น webhook จะเปลี่ยนสถานะเป็น `PAID`

## ขึ้นใช้งานจริง
- เปลี่ยนเป็น `sk_live_...` และสร้าง webhook endpoint ใหม่ในโหมด live (ได้ `whsec_...` ใหม่)
- `validateEnvironment` จะไม่ให้เซิร์ฟเวอร์ production เริ่มถ้าตั้ง `PAYMENT_PROVIDER=stripe` แต่ขาดคีย์
- ถ้า `PAYMENT_PROVIDER=stub` บน production พร้อมเพย์จะปิดและแนะนำให้จ่ายเงินสด

## ไฟล์ที่เกี่ยวข้อง
- `backend/src/payments/payment-gateway.ts` gateway stub/Stripe/พร้อมเพย์ตรวจสลิป และการแปลง event
- `backend/src/payments/promptpay-qr.ts` สร้าง payload Thai QR (EMVCo + CRC16)
- `backend/src/payments/payments.service.ts` สร้าง QR, `markPaidFromGateway`
- `backend/src/payments/payments.controller.ts` `POST /api/payments/stripe/webhook`
