# FixGo

แอปเรียกช่างซ่อมรถฉุกเฉิน — monorepo ของ backend, แอปลูกค้า, แอปช่าง และระบบหลังบ้าน

## โครงสร้าง

```
fixgo/
├── backend/            NestJS + Prisma + PostgreSQL (API + dispatch + ระบบเงิน)
├── apps/
│   ├── customer/       Flutter — แอปลูกค้าเรียกช่าง
│   └── provider/       Flutter — แอปช่างรับงาน
├── admin/              หน้าเว็บหลังบ้าน (HTML ไฟล์เดียว ไม่ต้อง build)
├── packages/
│   └── fixgo_core/     Dart package ใช้ร่วมกัน 2 แอป (ธีม, โมเดล, API client)
└── docs/               เอกสาร spec และการตัดสินใจทั้งหมด
```

## สิ่งที่ทำเสร็จแล้ว

**Backend** — คอมไพล์ผ่าน typecheck สะอาด
- ล็อกอินด้วยเบอร์โทร + OTP (ลูกค้า/ช่าง) และรหัสผ่านสำหรับแอดมิน
- แคตตาล็อกบริการ + ราคาตามประเภทรถ
- ลงทะเบียนช่าง, อนุมัติโดยแอดมิน, ออนไลน์/ออฟไลน์, อัปเดตพิกัด
- สร้างออเดอร์ + dispatch อัตโนมัติ (เรียงตามระยะทาง, timeout 5 นาที/คน, ส่งต่ออัตโนมัติ)
- วงจรสถานะงาน: กำลังหาช่าง → รับงาน → เดินทาง → ซ่อม → ปิดงาน
- ระบบเงิน: หักค่าธรรมเนียม 35%, กระเป๋าเงินช่างแบบ ledger, ขอเบิก/อนุมัติ/ปฏิเสธ
- ให้คะแนนช่าง + คำนวณคะแนนเฉลี่ย

**แอปลูกค้า (Flutter)** — `flutter analyze` ผ่านสะอาด
- ล็อกอิน OTP, หน้าแรก (หมวดบริการ), booking wizard 4 ขั้นตอน, ติดตามงาน, ประวัติ, จ่ายเงิน

**แอปช่าง (Flutter)** — `flutter analyze` ผ่านสะอาด
- ล็อกอิน OTP, แบบฟอร์มลงทะเบียน, สวิตช์ออนไลน์, งานเข้าพร้อมนับถอยหลัง, อัปเดตสถานะงาน, กระเป๋าเงิน + ขอเบิก

**หลังบ้าน** — ภาพรวม, อนุมัติช่าง, จัดการคำขอเบิกเงิน, ดูออเดอร์

## ยังไม่ได้ทำ (ต้องทำก่อนใช้งานจริง)

- **Payment gateway ของจริง** — ตอนนี้ `payments.service.ts` เป็น stub คืน QR ปลอม ต้องต่อ gateway จริงและตรวจลายเซ็น webhook ก่อน production
- **SMS gateway** — OTP ยังไม่ได้ส่งจริง โหมด development จะคืนรหัสกลับมาใน response เพื่อให้ทดสอบได้
- **GPS + แผนที่** — ทั้ง 2 แอปยังใช้พิกัดกลางกรุงเทพเป็นค่าคงที่ ต้องต่อ geolocator + Google Maps
- **Push notification** — ยังเป็น TODO ในโค้ด dispatch ตอนนี้แอปช่าง poll ทุก 10 วินาทีแทน
- **อัปโหลดรูป** — รูปเครื่องมือช่าง/รูปปัญหารถยังใช้ URL ตัวอย่าง ต้องต่อ storage จริง
- ยังไม่มี unit test และยังไม่เคยรันกับฐานข้อมูลจริง (ยังไม่ได้รัน migration)

## วิธีรัน

### 1. Backend

```bash
cd backend
cp .env.example .env          # แล้วแก้ค่า DATABASE_URL และ secret ต่าง ๆ
npm install
npx prisma migrate dev --name init
npm run prisma:seed           # ใส่หมวดบริการ + ราคาตั้งต้น
npx ts-node prisma/create-admin.ts 0812345678 "แอดมิน" รหัสผ่านที่ต้องการ
npm run start:dev             # http://localhost:3000
```

ต้องมี PostgreSQL รันอยู่ก่อน เช่น

```bash
docker run --name fixgo-db -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16
```

### 2. แอปมือถือ

```bash
cd apps/customer   # หรือ apps/provider
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

`10.0.2.2` คือ localhost ของเครื่องแม่เมื่อรันบน Android emulator
ถ้ารันบนมือถือจริงให้ใช้ IP ของเครื่องที่รัน backend แทน

### 3. หลังบ้าน

เปิด `admin/index.html` ด้วยเบราว์เซอร์ได้เลย ไม่ต้อง build
ถ้า backend ไม่ได้อยู่ที่ `http://localhost:3000` ให้ตั้งค่าใน console ของเบราว์เซอร์

```js
localStorage.setItem('fixgo_api_base', 'https://api-ของคุณ')
```

## การตัดสินใจหลักที่ฝังอยู่ในโค้ด

| เรื่อง | ค่า | อยู่ที่ไหน |
|---|---|---|
| ค่าธรรมเนียมแอป | 35% ทุกงาน | `backend/src/common/constants.ts` |
| เวลาให้ช่างกดรับงาน | 5 นาที/คน | `backend/src/common/constants.ts` |
| รัศมีค้นหาช่าง | 25 กม. | `backend/src/common/constants.ts` |
| จำนวนช่างสูงสุดต่อออเดอร์ | 10 คน | `backend/src/common/constants.ts` |
| สีแบรนด์ | ส้ม FixGo `#F26B1D` + หมึก `#1D2330` พื้นเทาอ่อน การ์ดมุมโค้ง | `packages/fixgo_core/lib/src/theme.dart` |

จำนวนเงินทุกจุดเก็บเป็น **สตางค์ (integer)** ไม่ใช่ทศนิยม เพื่อไม่ให้เกิดเศษเพี้ยนจาก floating point

รายละเอียด spec และเหตุผลเบื้องหลังการตัดสินใจอยู่ใน `docs/` และ `DESIGN.md`

## ที่มาของไอคอนและฟอนต์ (Third-party Attribution)

- ไอคอนหมวดบริการ 3D ส่วนใหญ่มาจาก **Microsoft Fluent Emoji** ([github.com/microsoft/fluentui-emoji](https://github.com/microsoft/fluentui-emoji)) สัญญาอนุญาต **MIT License** เก็บไฟล์ต้นฉบับไว้ที่ `packages/fixgo_core/assets/icons/licenses/fluentui-emoji-LICENSE.txt` ต้องให้เครดิตครบตาม license ก่อน publish ขึ้น store จริง
- `tow.png`, `tire.png` และโลโก้ FixGo วาดขึ้นใหม่สำหรับโปรเจกต์นี้
- ฟอนต์ **Noto Sans Thai** สัญญาอนุญาต SIL Open Font License อยู่ที่ `packages/fixgo_core/assets/fonts/OFL.txt`
