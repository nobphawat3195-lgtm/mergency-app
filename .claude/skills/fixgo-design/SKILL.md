---
name: fixgo-design
description: กฎแบรนด์ ธีมสีเขียว และขั้นตอนตรวจงาน UI ของ FixGo (ลูกค้า) และ FixGo Fixer (ช่าง) ใช้ทุกครั้งก่อนแก้หน้าจอ ไอคอน โลโก้ ข้อความราคา/สถานะชำระเงิน หรือเมื่อต้องถ่ายภาพหน้าจอส่งงาน
---

# FixGo design & delivery skill

## อ่านก่อนเริ่ม
1. `DESIGN.md` (token สี, contrast ที่ผ่านแล้ว, layout หน้าแรกทั้ง 2 แอป, data honesty rules)
2. `packages/fixgo_core/lib/src/theme.dart` (`FixGoColors`, `fixGoBrandGradient`, `buildFixGoTheme`)
3. `git status` และ diff ที่ค้างอยู่ ห้ามทับงานที่ยังไม่ commit

## กฎที่ห้ามละเมิด
- สีใช้จาก `FixGoColors` เท่านั้น: เขียวเข้ม `#0B5F45`, หยก `#16A37B`, มิ้นต์ `#ECF8F1`, หมึก `#122821`, มะนาว `#C7EE77`
- ปุ่ม "เรียกช่างด่วน" ต้องเด่นที่สุดบนหน้าแรกลูกค้า
- ภาพ mockup เป็นแนวทางภาพเท่านั้น ห้ามคัดลอกตัวเลข/คำโฆษณาในภาพไปเป็นข้อมูลจริง
- ราคา จำนวนจุดตรวจ รายได้ จำนวนงาน ต้องมาจาก API
- ห้ามแสดง "ชำระแล้ว" จาก QR หรือการกดปุ่ม ใช้ `Order.isPaid` (backend `PAID`) และ `paymentStatusLabel()` ร่วมกันทั้ง 2 แอป
- ป้ายสถานะงานใช้ `orderStatusLabel()` จาก core เท่านั้น ลูกค้าและช่างต้องเห็นเหมือนกัน
- เมนูจั๊มแบตเรียก `BookingFlow(initialSubServiceKeyword: 'จั๊ม')` ต้องข้ามไปขั้นเลือกประเภทรถทันที
- งานตรวจรถ: ช่างถ่ายรูปด้วยกล้องของเครื่องก่อน แล้วแนบจากคลังรูป (`pickMultiImage`) ไม่เปิดกล้องจากในแอป
  - ภาพหลักฐานแยกช่องตามหัวข้อ (ประตูหน้าซ้าย/ขวา, เสา A/B/C, ห้องเครื่อง, รูปตำหนิ ฯลฯ) นิยามที่เดียวใน `backend/src/inspections/photo-slots.ts`
  - ช่องบังคับต้องมีรูปก่อนส่งรายงาน รูปตำหนิต้องระบุตำแหน่งและอาการทุกรูป
- แหล่งข้อมูลที่ตรวจสอบไม่ได้ (เช่น TRUSTCAR 360) แสดงสถานะ "ต้นแบบ" และไม่เปิดจอง
- ห้ามบอกว่าพร้อมลง App Store/Google Play ถ้ายังไม่มีหลักฐาน build APK/IPA และทดสอบบนเครื่องจริง

## โลโก้และไอคอน
- ต้นฉบับ: `tool/brand/fixgo_logo.svg`, `tool/brand/fixgo_fixer_logo.svg`
- เรนเดอร์: `PLAYWRIGHT_MODULE=<path>/playwright node tool/brand/render_icons.mjs <outDir>` แล้วย่อไปยัง mipmap / AppIcon / web icons

## ตรวจงานก่อนส่ง
1. `flutter analyze` ใน `packages/fixgo_core`, `apps/customer`, `apps/provider`
2. backend: `npm run typecheck` และ `npx jest`
3. `flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://localhost:3000` (แอปช่างไม่มีโฟลเดอร์ web ใน repo: `flutter create --platforms web .` ชั่วคราว แล้วลบ `web/`, `test/` และคืน `.metadata` หลัง build)
4. ถ่ายภาพหน้าจอด้วย Playwright ที่ 390×844 (iPhone) และ 412×915 (Android) ต่อ backend จริง
   - เปิด semantics ด้วยการคลิก `flt-semantics-placeholder` ก่อน แล้วหา element จาก `aria-label`
   - ช่อง OTP คือ `input:not([disabled])` ตัวสุดท้าย รหัส dev อยู่ใน log ของ backend
5. รายงาน: ภาพหน้าจอ ผลทดสอบ ไฟล์ที่แก้ และรายการที่ยังขาดก่อนเผยแพร่จริง
