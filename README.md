# FixGo

Web app และแอปเรียกช่างรถยนต์นอกสถานที่ พร้อมระบบรับงานสำหรับช่างและหลังบ้านสำหรับผู้ดูแล ครอบคลุมตั้งแต่แชร์ตำแหน่ง ส่งรูป ประเมินราคา อนุมัติราคาก่อนซ่อม ไปจนถึงปิดงานและบันทึกรายได้ช่าง

## โครงสร้าง

```text
backend/                 NestJS + Prisma + PostgreSQL
apps/customer/           Flutter ลูกค้า (มือถือและ Web)
apps/provider/           Flutter ช่างรับงาน
admin/                    เว็บหลังบ้าน
packages/fixgo_core/     ธีม โมเดล API client และบริการตำแหน่งที่ใช้ร่วมกัน
docs/                     Product/UX specification
```

## ความสามารถที่มีแล้ว

### ลูกค้า

- ล็อกอินด้วยเบอร์โทรและ OTP พร้อมเก็บ session แบบ secure storage
- เลือกบริการ ประเภทรถ และส่งตำแหน่ง GPS ปัจจุบัน
- เขียนรายละเอียดและอัปโหลดรูปปัญหารถได้สูงสุด 5 รูป
- เปิดตำแหน่งใน Google Maps และโทรหาช่างจากหน้าติดตามงาน
- ดูสถานะงานและราคาประเมินแบบอัปเดตต่อเนื่อง
- อนุมัติหรือปฏิเสธราคาที่ช่างเสนอ ก่อนเริ่มซ่อม
- ชำระผ่าน PromptPay QR หลังช่างปิดงาน โดยรอ webhook ยืนยันยอดก่อนแสดงว่าชำระแล้ว
- จองตรวจรถมือสองราคาเดียว 1,990 บาท: กรอกยี่ห้อ/รุ่น/ปี ลิงก์ประกาศ ข้อมูลผู้ขาย และวันเวลานัด
- ดูรายงานตรวจรถ: เกรด A–E, คำแนะนำควรซื้อหรือไม่, ธงความเสี่ยงรถจมน้ำ/ชนหนัก/กรอไมล์/เอกสาร, จุดที่พบพร้อมรูป และคะแนนรายหมวด

### ช่าง

- ลงทะเบียนด้วยชื่อ เบอร์โทร ประสบการณ์ พื้นที่ เวลาให้บริการ ประเภทรถ และบริการที่รับ
- อัปโหลดรูปเครื่องมือจริงเพื่อให้แอดมินตรวจสอบ
- เปิด/ปิดรับงาน ส่ง heartbeat และตำแหน่งล่าสุด
- รับข้อเสนอเป็นชุดตามระยะทาง ป้องกันช่างที่กำลังมีงานรับซ้อน
- เสนอราคาและหมายเหตุ รอลูกค้ายืนยันก่อนเริ่มงาน
- อัปเดตสถานะ เดินทาง/กำลังซ่อม/เสร็จสิ้น และรอระบบยืนยันการชำระเงิน
- กระเป๋ารายได้แบบ ledger และคำขอถอนเงิน

- ทำรายงานตรวจรถมือสอง 134 จุด 11 หมวด บันทึกอัตโนมัติ กรอกค่าวัด (ความหนาสี ดอกยาง ผ้าเบรก แบต ฯลฯ) แล้วระบบตัดสินผ่าน/ไม่ผ่านให้ ข้อที่ไม่ผ่านต้องถ่ายรูปประกอบ และต้องส่งรายงานก่อนปิดงาน

### ผู้ดูแลและเซิร์ฟเวอร์

- อนุมัติช่าง ดูงาน และจัดการคำขอถอนเงิน
- ป้องกันการเข้าถึงออเดอร์ของผู้อื่น (ownership/role checks)
- Dispatch ช่างออนไลน์ที่ heartbeat ไม่เก่า ตามระยะทางและเวลาทำงาน
- เสนองานครั้งละ 4 คน รอบละ 90 วินาที สูงสุด 12 คน ภายใน 25 กม.
- บันทึกรายได้แบบ idempotent ป้องกันเครดิตซ้ำ
- จำกัดการขอ/เดา OTP และไม่ส่ง OTP กลับใน production
- CORS allow-list, secret validation, signed webhook และ health check
- Presigned upload สำหรับ S3-compatible storage
- SMS จริงผ่าน Twilio หรือ console ใน development
- Migration เริ่มต้น, unit tests และ GitHub Actions CI

## โหมดตรวจรถมือสอง

- รายการตรวจอยู่ที่ `backend/src/inspections/checklist.ts` เป็นแหล่งข้อมูลเดียว แอปดึงผ่าน `GET /api/inspections/checklist` ไม่ hardcode ในแอป
- หมวด: เอกสารและตัวตนรถ, โครงสร้างตัวถัง, สีและตัวถัง (วัดความหนาสี 11 ชิ้น), ร่องรอยรถจมน้ำ, ห้องเครื่อง, สแกน OBD2, ระบบไฮบริด/EV, ช่วงล่างและเบรก, ยางและล้อ, ห้องโดยสารและไฟฟ้า, ทดลองขับ
- การให้คะแนน (`grading.ts`): ข้อสำคัญมีน้ำหนัก 3 เท่า ข้อสำคัญไม่ผ่านแม้ข้อเดียว, สงสัยรถจมน้ำ หรือเอกสารไม่ตรง = ไม่แนะนำให้ซื้อ
- API: `GET/PATCH /api/orders/:id/inspection`, `POST /api/orders/:id/inspection/submit` ลูกค้าเห็นผลรายข้อเฉพาะหลังช่างส่งรายงาน
- ถ้าแก้ความหมายของรายการตรวจ ให้เพิ่ม `CHECKLIST_VERSION`

## ส่วนที่ต้องเชื่อมก่อนเปิด production

โค้ดเตรียมจุดเชื่อมไว้แล้ว แต่ต้องมีบัญชีและ credential ของเจ้าของระบบ:

1. **Push notification** — ตอนนี้แอปช่างตรวจงานใหม่ทุก 10 วินาที ต้องสร้าง Firebase project และเพิ่ม FCM/APNs เพื่อแจ้งเตือนเมื่อแอปอยู่เบื้องหลัง
2. **Payment gateway** — รับเฉพาะ PromptPay QR และยังเปิดรับเงินจริงไม่ได้จนกว่าจะเชื่อมบัญชี Stripe, webhook secret และทดสอบ sandbox ครบวงจร
3. **SMS** — ตั้งค่า Twilio หรือเปลี่ยน adapter เป็นผู้ให้บริการ SMS ไทย
4. **Object storage** — ตั้ง S3/R2/Spaces และ CORS ของ bucket เพื่อรับรูปจาก Flutter Web
5. **แผนที่เชิงภาพ** — แชร์ GPS และเปิด Google Maps ได้แล้ว แต่ยังไม่ได้ฝังแผนที่/เส้นทางแบบ live ในแอป
6. **Store release** — ต้องมี Apple Developer/Google Play Console, signing key, privacy policy และ Firebase config ของแอปจริง

อย่าเปิด production ด้วย development fallback ระบบจะตรวจ secret ที่จำเป็นและหยุดทำงานทันทีหากตั้งค่าไม่ครบ

## วิธีรัน Backend

```bash
cd backend
cp .env.example .env
npm ci
npm run prisma:generate
npx prisma migrate deploy
npm run prisma:seed
npx ts-node prisma/create-admin.ts 0812345678 "แอดมิน" รหัสผ่านที่ปลอดภัย
npm run start:dev
```

ต้องมี PostgreSQL ก่อน เช่น:

```bash
docker run --name fixgo-db -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
```

ตรวจคุณภาพ:

```bash
npm run typecheck
npm test
npm run build
```

## วิธีรัน Flutter

```bash
cd apps/customer        # หรือ apps/provider
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

สำหรับ Web:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

`10.0.2.2` คือ localhost ของเครื่องแม่จาก Android emulator หากใช้มือถือจริงให้เปลี่ยนเป็น IP/HTTPS API ที่มือถือเข้าถึงได้

## หลังบ้าน

เปิด `admin/index.html` ผ่าน web server และตั้ง API base URL เมื่อต้องการ:

```js
localStorage.setItem('fixgo_api_base', 'https://api.example.com')
```

โทเคนแอดมินเก็บใน `sessionStorage` และ dynamic HTML ถูก escape เพื่อลดความเสี่ยง XSS

## ค่าธุรกิจหลัก

| เรื่อง | ค่า |
|---|---:|
| ค่าธรรมเนียมแพลตฟอร์ม | 35% |
| รอบเวลารับงาน | 90 วินาที |
| ช่างต่อรอบ | 4 คน |
| ช่างสูงสุดต่อออเดอร์ | 12 คน |
| รัศมีค้นหา | 25 กม. |
| ตรวจรถมือสอง | 1,990 บาท ราคาเดียว |
| ราคาบริการอื่น | ถูกกว่า 24CarFix 101 บาททุกรายการ (`DISCOUNT_VS_24CARFIX` ใน `backend/prisma/seed.ts`) |

จำนวนเงินในฐานข้อมูลเก็บเป็น **สตางค์ (integer)** เพื่อไม่ให้เกิดความคลาดเคลื่อนจากเลขทศนิยม

## Attribution

- ไอคอนหมวดบริการ 3D ชุดหลัก (ซ่อมรถ แบตเตอรี่ ยาง กุญแจ น้ำมัน รถยก รถ EV ตรวจรถ) จัดทำโดยเจ้าของโปรเจกต์
- ไอคอนสายฟ้า ไซเรน และช่าง มาจาก [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji) (MIT License) เก็บ license ไว้ที่ `packages/fixgo_core/assets/icons/licenses/fluentui-emoji-LICENSE.txt`
- ฟอนต์ Noto Sans Thai สัญญาอนุญาต SIL Open Font License อยู่ที่ `packages/fixgo_core/assets/fonts/OFL.txt`
