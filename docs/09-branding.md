# 9. Branding — MechNow

## ชื่อแบรนด์

**MechNow** — ชื่อแอปที่จะขึ้น App Store / Play Store
- Tagline แนะนำ: "เรียกช่างทันที ช่างใกล้คุณพร้อมช่วย"
- Package/Bundle ID แนะนำ: `com.fixgo.customer`, `com.fixgo.provider`, `com.fixgo.admin`

## Design Direction (อ้างอิงจากภาพ Antixor Taxi ที่เลือก)

โทนสีเข้ม + เหลือง-ทอง ให้ความรู้สึกมั่นใจ น่าเชื่อถือ ตัดกันชัดเจน อ่านง่ายแม้ใช้งานกลางแดด/ตอนกลางคืนตอนรถเสีย

### Color Palette

| Token | Hex | ใช้ที่ไหน |
|---|---|---|
| `primary` (Navy) | `#0B1B2B` | Header, background ส่วน hero, bottom nav |
| `accent` (Yellow/Gold) | `#FFC72C` | ปุ่มหลัก (CTA), badge "แนะนำ", highlight ราคา |
| `background` | `#FFFFFF` | พื้นหลังหลักของ content area |
| `surface` | `#F5F6F8` | พื้นหลัง card รอง |
| `text-primary` | `#0B1B2B` | ข้อความหลัก |
| `text-secondary` | `#6B7280` | คำอธิบาย/subtitle |
| `success` | `#22C55E` | สถานะ "เสร็จสิ้น", คะแนนสภาพรถดี (สำหรับ Phase 2 inspection) |
| `warning` | `#F59E0B` | สถานะ "กำลังดำเนินการ" |
| `error` | `#EF4444` | สถานะยกเลิก/ปัญหา |

### Typography

- Font แนะนำ: **Noto Sans Thai** (รองรับไทย+อังกฤษ อ่านง่ายบนมือถือ, ฟรีใช้เชิงพาณิชย์ได้) จับคู่กับ **Inter** สำหรับตัวเลข/อังกฤษล้วน (ราคา, เวลา)
- Heading: bold, ขนาดใหญ่ชัดเจน (ตาม reference ที่ใช้ heading ตัวหนามาก)
- Body: regular, เว้นบรรทัดกว้างเพื่อความอ่านง่าย (สำคัญมากสำหรับ user กลุ่มที่ไม่มีความรู้เรื่องรถ/ผู้สูงอายุ)

### UI Pattern ที่ยืมจาก reference มาปรับใช้กับแอป mobile

- **ปุ่ม CTA หลัก**: พื้นเหลือง ตัวหนังสือ navy ตัวหนา ขอบมน (rounded pill) — ใช้กับปุ่ม "เรียกช่างฉุกเฉิน", "ยืนยันเรียกช่าง"
- **Card แบบ rounded + shadow เบา**: ใช้กับ card บริการ, card สรุปราคา, card ประวัติงาน
- **Section header แบบมี label เล็กสีเหลืองด้านบน** (เช่น "GET THE APP" ในภาพ) → ปรับใช้กับหัวข้อ section ในหน้า Home
- **Icon วงกลมพื้นเข้ม ไอคอนเหลือง** (จากส่วน "Why Choose Us" ในภาพ) → ใช้กับหมวดหมู่บริการในหน้า Home แทน emoji

### หลักการ "เข้าใจง่ายที่สุด" (ตามที่ขอ)

1. ทุกปุ่มสำคัญใช้สีเหลืองเท่านั้น (ไม่มีปุ่มสีอื่นแข่งกันดึงความสนใจ) — ผู้ใช้ไม่งง ว่าต้องกดอะไรต่อ
2. ราคาต้องเป็นตัวเลขใหญ่ ชัดเจน ไม่ใช้ font บางเกินไป
3. ไอคอนประกอบข้อความเสมอ ไม่ใช้ไอคอนอย่างเดียวโดยไม่มี label (กลุ่มเป้าหมายไม่มีความรู้เรื่องรถ ต้องไม่ต้องตีความเอง)
4. ขั้นตอนที่ซับซ้อน (เช่น booking wizard 4 steps) ต้องมี progress indicator ให้เห็นเสมอว่าอยู่ขั้นไหน เหลืออีกกี่ขั้น

## สรุปสถานะ Spec

ทุกการตัดสินใจหลักที่จำเป็นต่อการเริ่ม scaffold โค้ดครบแล้ว:
- ✅ ขอบเขต MVP, พื้นที่เปิดตัว, จำนวนช่างเริ่มต้น
- ✅ สถาปัตยกรรมระบบ (Flutter + NestJS + PostgreSQL)
- ✅ Business logic (dispatch, commission, payment, withdrawal)
- ✅ แบบฟอร์มลงทะเบียนช่าง (ของจริง)
- ✅ ชื่อแบรนด์ (MechNow) + Design direction

**พร้อมเริ่ม scaffold โครงสร้างโปรเจกต์แล้ว**
