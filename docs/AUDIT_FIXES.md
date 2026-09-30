# ผลแก้ไข FixGo จากการตรวจโค้ด 30 กันยายน 2026

แก้ไขจาก `main` commit `a75ee348e5f446a4627d8630862b51b82be7052b` เพื่อป้องกันยอดเงินผิดและสถานะงานขัดกันเมื่อคำขอเข้าพร้อมกัน

| ข้อที่พบ | พฤติกรรมหลังแก้ | หลักฐานทดสอบ |
|---|---|---|
| จ่ายแล้วแต่เครดิตรายได้ล้มเหลว | PAID และ ledger อยู่ใน transaction เดียวกัน ล้มเหลวแล้ว rollback ทั้งคู่ | จำลอง ledger ล่มและ retry บน PostgreSQL |
| เงินสดชนพร้อมเพย์ | PENDING เปลี่ยนเป็น PAID ได้ครั้งเดียว มี ledger เพียงช่องทางเดียว | ส่งสองวิธีพร้อมกันและ webhook ซ้ำ 5 ครั้ง |
| คืนยอดเบิกซ้ำ | เปลี่ยน REQUESTED ก่อนคืนยอดใน transaction พร้อม idempotency key | ปฏิเสธพร้อมกันสองครั้ง |
| โอนยอดเบิกชนการปฏิเสธ | ทั้งสองคำสั่งต้องเปลี่ยนจาก REQUESTED ได้ก่อน | โอนและปฏิเสธพร้อมกัน ตรวจสถานะกับ balance |
| ยกเลิกงานชนเริ่มเดินทาง | คำสั่งเปลี่ยนสถานะตรวจสถานะเดิมเสมอ ยกเลิกแล้วปิดข้อเสนอที่ค้าง | cancellation/en-route race และ offers cleanup |
| ลูกค้ายืนยันราคาเก่า | ยืนยันด้วย quoteVersion และยอดที่หน้าจอแสดง ราคา PENDING/APPROVED เปลี่ยนทับไม่ได้ | stale version ทั้งที่ยอดเท่าเดิม |
| สลิปลูกค้าออกไปถึงช่าง | endpoint ของช่างคืนเฉพาะ payment summary | ตรวจ response ของลูกค้าและช่าง |
| ช่างระงับรับข้อเสนอเดิมได้ | ตรวจ VERIFIED, isOnline, deletedAt และเพดานหนี้ใน transaction ตอนรับ | รับข้อเสนอหลังระงับ |
| ลบบัญชีทั้งที่ติดหนี้ | ต้องไม่เหลือยอดบวก/ลบ งานค้างชำระ หรือสลิปรอตรวจ รายงานเงินยังรวมบัญชีที่ลบแล้ว | ปฏิเสธการลบเมื่อมีหนี้ และ historical debt report |
| งานนัดล็อกช่างตั้งแต่จอง | นัดอนาคตคงสถานะ CREATED จนถึง 1 ชั่วโมงก่อนนัด แล้ว cron เริ่มหาช่าง | นัดอนาคต/ถึงช่วงหา และ validation วันนัด |
| รายงานแก้ชนการส่ง | อ่าน ตรวจ แก้/ส่งใน serializable transaction แล้ว retry เมื่อ DB conflict | ส่งพร้อมแก้ผลโครงสร้าง ตรวจ verdict กับข้อมูล |
| จองบริการปิดใช้งาน | ตรวจ active ของหมวด บริการ และประเภทรถ | ปิดแต่ละชนิดแล้วเรียก quote |
| เลขงานสุ่มชนกัน | ใช้ sequence ของ PostgreSQL เลขใหม่รูปแบบ FGวันที่-เลขลำดับ | จองพร้อมกัน 5 รายการ ต้องได้เลขไม่ซ้ำ |
| คะแนนเฉลี่ยชนกัน | รวมคะแนนจริงภายใน serializable transaction | ให้คะแนน 1 และ 5 พร้อมกัน ต้องได้เฉลี่ย 3 จำนวน 2 |
| คำขอแอปค้าง | request timeout 25 วินาที อัปโหลด 60 วินาที แจ้งผู้ใช้ตรวจสถานะก่อนทำรายการซ้ำ | Flutter MockClient จำลอง timeout/offline และตรวจ payload ราคา |
| OTP เดียวใช้ล็อกอินพร้อมกันหลายครั้ง | เปลี่ยน consumed ด้วย conditional update; ตรวจ expiry และจำนวนครั้งที่ใส่ผิดอีกครั้งก่อนออก token | HTTP ส่งรหัสเดียวพร้อมกัน 5 คำขอ ต้องผ่านเพียง 1 คำขอ |
| ขอ OTP พร้อมกันข้าม cooldown และส่ง SMS ซ้ำ | ตรวจ cooldown และออก OTP ใน serializable transaction; SMS ส่งหลัง commit และยกเลิกเฉพาะรหัสที่ส่งล้มเหลว | HTTP ขอ OTP พร้อมกัน 5 คำขอ ต้องออกเพียง 1 รหัส อีก 4 ได้ 429 |

| URL รูปช่างที่อัปโหลดก่อนส่งใบสมัครมีเบอร์โทรหรือ LINE userId (`provider-tools/pending:<เบอร์>/…`) และไปแสดงในลิงก์ติดตามสาธารณะ | โฟลเดอร์ของบัญชีที่ยังไม่สมัครเป็น HMAC ของ sub (`p-…`) บัญชีที่สมัครแล้วใช้ id เดิม | unit test ทั้งเบอร์และ LINE, HTTP smoke สมัครช่างผ่าน API แล้วตรวจ URL ที่บันทึก, staging ตรวจลิงก์ติดตามสาธารณะ |

ข้อมูลเดิม: ช่างที่สมัครก่อนแก้นี้ยังมี URL รูปแบบเดิมในฐานข้อมูล ตรวจด้วย query อ่านอย่างเดียว
`SELECT id FROM "Provider" WHERE "photoUrl" LIKE '%/pending:%';`
ถ้าพบ ให้ช่างอัปโหลดรูปหน้าตรงใหม่ในแอป ห้ามแก้ URL ในฐานข้อมูลตรงๆ เพราะไฟล์ยังอยู่ที่ path เดิม

## งานนัดตรวจรถ

- นัดที่มีวันเวลา: API รับช่วง 1 ชั่วโมงถึง 30 วันล่วงหน้า
- ระบบเริ่มหาช่างก่อนนัดประมาณ 1 ชั่วโมง และตรวจรอบใหม่ทุก 30 วินาที
- ข้อเสนอในแอปช่างแสดงวันเวลานัดให้ตัดสินใจก่อนรับ
- หน้าจองแจ้งว่าการบันทึกนัดยังไม่ใช่การยืนยันว่ามีช่างรับงาน
- ถ้าไม่ระบุวันเวลา ถือเป็นงานเรียกทันทีตามพฤติกรรมเดิม
- รุ่นนี้ยังไม่มีระบบจองปฏิทินช่างล่วงหน้าและรับประกันเวลานัด ต้องประเมินการให้บริการจริงก่อนใช้คำโฆษณารับประกัน

## การทดสอบ

Backend:

```sh
cd backend
npm ci
npm run prisma:generate
npm run typecheck
npm test
npm run build
npm run build:scripts
```

PostgreSQL integration (ใช้เฉพาะฐานข้อมูลทดสอบ):

```sh
export DATABASE_URL='postgresql://fixgo_test:password@127.0.0.1:5432/fixgo_audit_test?schema=public'
export FIXGO_TEST_DATABASE_URL="$DATABASE_URL"
npm run migrate:deploy
npm run test:integration
npm run build
npm run test:http
```

ชุด integration ตรวจชื่อฐานข้อมูลและ host ก่อนรัน รับเฉพาะ localhost/127.0.0.1 และฐานข้อมูล `fixgo_audit_test` และล้างข้อมูลเฉพาะฐานนี้ทุกเคส ห้ามตั้งให้ชี้ฐานข้อมูลใช้งานจริง

Flutter: `flutter pub get`, `flutter analyze`, `flutter test` ใน `packages/fixgo_core` และ `apps/customer`; `flutter pub get`, `flutter analyze` และ `flutter test` พร้อม build web ใน `apps/provider` (เพิ่มชุดทดสอบคืน session ช่างเมื่อออฟไลน์/timeout)

ผลตรวจ local: Backend unit 156 เคส, PostgreSQL integration 24 เคส, Flutter shared 13 เคส, customer 2 เคส และ provider 5 เคส ผ่านทั้งหมด รวม 200 เคส; typecheck/build backend, analyze ทั้ง 3 Flutter projects และ release web build ทั้ง 2 แอปผ่าน ใช้ Flutter 3.47.5 / Dart 3.13.4 และ PostgreSQL 16

ทดสอบ HTTP เพิ่ม 20 สถานการณ์ โดยเปิด API ที่ build แล้วจริงกับ PostgreSQL และไฟล์อัปโหลด local: OTP/cooldown พร้อมกัน, แยกสิทธิ์ owner/staff/customer/provider, อนุมัติช่าง, จอง/รับงาน/เดินทาง/ราคา/ปิดงาน, QR และสลิป, เงินสด, คะแนน, เบิก/คืนยอด, นัดอนาคต, รายงานตรวจรถพร้อมภาพหลักฐาน, ชำระหนี้ค่าคอม, ระงับช่าง, ลบบัญชี และ audit log. สคริปต์รับเฉพาะฐานข้อมูลทดสอบ local ชื่อเดียวกับ integration และล้างข้อมูลก่อนรัน ใช้ SMS/push แบบ console และพร้อมเพย์จำลอง ไม่มีการโอนเงินจริง

Web build ใช้ JavaScript ตามเดิม ยังไม่รองรับ Wasm เพราะ dependency secure storage รุ่นปัจจุบัน GitHub Actions ของ commit แรกใน PR build APK/AAB ของทั้งสองแอปสำเร็จ มี artifacts ให้ติดตั้งทดสอบ แต่ยังไม่ได้ยืนยัน release signing/API URL/Firebase ของระบบจริง และยังไม่ครอบคลุม native plugins บนมือถือจริงหรือ iOS build ของการเปลี่ยนแปลงนี้

GitHub CI job `backend-integration` ใช้ PostgreSQL 16 แยกจากระบบจริง และรันทั้ง integration กับ HTTP smoke ต่อกัน

## การนำขึ้นใช้งาน

1. สำรองฐานข้อมูลและบันทึก image/release เดิมก่อนเปลี่ยนระบบ
2. ติดตั้ง migrations สองรายการ: `20260930040000_quote_version` และ `20260930041000_order_number_sequence`
3. ปล่อย backend และแอปลูกค้า/เว็บจาก commit เดียวกัน แอปรุ่นเดิมที่ไม่ส่ง quoteVersion และ priceProposed จะยืนยันราคาไม่ได้ (400) ต้องแจ้งอัปเดตแอปก่อนรับงานรุ่นใหม่
4. ทดสอบ staging ครบวงจร: จอง → รับงาน → เดินทาง → เสนอ/ยืนยันราคา → เริ่มงาน → ปิดงาน → จ่าย → เบิก; งานตรวจรถต้องทดสอบส่งรายงานด้วย
5. ทดสอบ SMS, LINE, push ใน background บนมือถือ และ payment gateway sandbox ของผู้ให้บริการแยกต่างหาก ชุดทดสอบ local ใช้ notification doubles และไม่ยืนยันความพร้อมของบัญชีบริการจริง
6. Webhook ที่แจ้งเงินเข้าอีกวิธีหรืออีก charge หลัง PAID จะไม่สร้าง ledger ซ้ำ และแจ้งทีมงานผ่านช่องทาง admin alert ที่ตั้งไว้ ให้ตรวจเงินเข้าจริงก่อนดำเนินการคืนเงิน

ถ้าย้อน backend/app กลับรุ่นเดิม ไม่ต้องลบคอลัมน์หรือ sequence ที่เพิ่ม (additive migrations) แต่พฤติกรรมเก่าจะยังมีบั๊กเดิม ห้ามถือว่าการ rollback แก้ข้อมูลเงินที่ผิดได้

## ผลซ้อมอัปเกรดบน staging (30 กันยายน 2026)

ระบบ staging คือชุด production เดียวกับ `deploy/` (docker compose, Caddy HTTPS, PostgreSQL, SMS โหมดทดลอง, พร้อมเพย์แบบแนบสลิป) รันบนเครื่องทดสอบ ยังไม่ใช่ VPS จริง

1. ก่อนอัปเกรด: สร้างงานที่ช่างเสนอราคาค้างไว้ (PENDING) ด้วย API รุ่นเดิม เพื่อจำลองงานที่กำลังทำอยู่ตอนปล่อยรุ่นใหม่
2. สำรอง: `deploy/backup.sh` (ฐานข้อมูลและรูป) และ tag image เดิมเป็น `fixgo-rollback/*` กู้ไฟล์สำรองลงฐานข้อมูลแยกแล้วนับแถวตรงกับต้นฉบับ
3. อัปเกรด: `sudo bash deploy/install.sh` บน commit ใหม่ API ติดตั้ง migrations ทั้งสองรายการตอนเริ่ม และ `deploy/doctor.sh` ผ่าน
4. งานที่ค้างข้ามรุ่นได้ `quoteVersion = 0` แอปรุ่นเดิมที่ไม่ส่ง version ถูกปฏิเสธ (400) ส่วนแอปรุ่นใหม่ส่ง version 0 กับยอดที่เห็นแล้วยืนยันได้และจ่ายเงินจนจบงาน
5. ทดสอบครบวงจรผ่าน HTTPS (81 รายการ ผ่านทั้งหมด): ล็อกอิน OTP โหมดทดลอง, สมัครและอนุมัติช่าง, จอง, รับงาน, เดินทาง, ลิงก์ติดตามสาธารณะ, เสนอราคา → ลูกค้าปฏิเสธ → เสนอใหม่ → ยืนยันราคาเก่าถูกปฏิเสธ (409) → ยืนยันราคาปัจจุบัน, เริ่มงาน, ปิดงาน, เงินสดยืนยันซ้ำไม่คิดค่าคอมซ้ำ, QR พร้อมเพย์ + สลิป + เจ้าของยืนยันซ้ำไม่เครดิตซ้ำ, ให้คะแนน, เบิกเงิน (ปฏิเสธคืนยอดครั้งเดียว/โอนหักครั้งเดียว), นัดตรวจรถล่วงหน้า, ตรวจรถ 134 จุดพร้อมรูปหลักฐานและล็อกรายงาน, ชำระหนี้ค่าคอมด้วย QR + สลิป, แอดมินยกเลิกงานที่ไม่มีช่างรับ, audit log และรายงานการเงิน
6. Query ตรวจเงินย้อนหลังด้านล่างรันใน transaction แบบอ่านอย่างเดียวบน staging ได้ 0 แถวทั้งสามข้อ

ยังไม่ได้ทดสอบบน staging: LINE Login กับบัญชีจริง, SMS จริง, push บนมือถือตอนแอปอยู่เบื้องหลัง, payment gateway sandbox และแอปที่ติดตั้งบนมือถือจริง

## ตรวจข้อมูลเงินย้อนหลัง

การแก้โค้ดป้องกันรายการใหม่ ข้อมูลผิดที่เคยเกิดขึ้นต้องตรวจเทียบกับเงินจริง ไม่ปรับยอดย้อนหลังอัตโนมัติ ใช้ query แบบอ่านอย่างเดียวต่อไปนี้ค้นหารายการให้ทีมงานตรวจ:

```sql
-- ชำระแล้วแต่ไม่มี ledger ที่ตรงกับวิธีรับเงิน
SELECT p.id, o."orderNo", p.method, p.amount
FROM "Payment" p JOIN "Order" o ON o.id = p."orderId"
WHERE p.status = 'PAID' AND NOT EXISTS (
  SELECT 1 FROM "WalletEntry" w
  WHERE w."orderId" = o.id AND (
    (p.method = 'CASH' AND w.type = 'COMMISSION_DUE') OR
    (p.method <> 'CASH' AND w.type = 'ORDER_EARNING')
  )
);

-- งานเดียวมีทั้งรายได้ออนไลน์และค่าคอมเงินสด
SELECT "orderId" FROM "WalletEntry"
WHERE type IN ('ORDER_EARNING', 'COMMISSION_DUE')
GROUP BY "orderId" HAVING COUNT(DISTINCT type) > 1;

-- คำขอเบิกที่มีการคืนยอดมากกว่าหนึ่งครั้ง
SELECT "withdrawalId", COUNT(*), SUM(amount)
FROM "WalletEntry"
WHERE type = 'ADJUSTMENT' AND "withdrawalId" IS NOT NULL
GROUP BY "withdrawalId" HAVING COUNT(*) > 1;
```
