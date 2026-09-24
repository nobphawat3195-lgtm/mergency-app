---
version: beta
name: FixGo
description: >
  Design system ของแอป FixGo — เรียกช่างซ่อมรถฉุกเฉิน กลุ่มเป้าหมายไม่มีความรู้เรื่องรถ
  และมักเปิดแอปตอนเครียด (รถเสีย กลางคืน กลางแดด) โทนสว่าง พื้นเทาอ่อน การ์ดขาวมุมโค้ง
  ส้ม FixGo เป็นสีหลักของทุก action ไอคอนหมวดบริการแบบ 3D ที่สื่อความหมายตรง
  เลย์เอาต์หน้าแรกแบบ bento (การ์ดฉุกเฉินใหญ่ + ทางลัด) อ้างอิงแนวทางแอปบริการรถในไทย
  แต่ใช้แบรนด์ โลโก้ ข้อความ และภาพของ FixGo เองทั้งหมด
colors:
  navy: "#1D2330"
  primary: "{colors.accent}"
  accent: "#F26B1D"
  accent-active: "#D9560A"
  accent-soft: "#FFF1E7"
  background: "#FFFFFF"
  surface: "#F5F6F8"
  text-primary: "#1D2330"
  text-secondary: "#6B7280"
  success: "#16A34A"
  warning: "#F59E0B"
  error: "#DC2626"
  hairline: "#E8EAEE"
typography:
  headline:
    fontFamily: Noto Sans Thai
    fontSize: 24px
    fontWeight: 800
    lineHeight: 1.3
  title:
    fontFamily: Noto Sans Thai
    fontSize: 17px
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: Noto Sans Thai
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.5
  caption:
    fontFamily: Noto Sans Thai
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
  price:
    fontFamily: Noto Sans Thai
    fontSize: 24px
    fontWeight: 800
    lineHeight: 1.2
  button:
    fontFamily: Noto Sans Thai
    fontSize: 17px
    fontWeight: 700
    lineHeight: 1.2
  label:
    fontFamily: Noto Sans Thai
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.3
  nav-label:
    fontFamily: Noto Sans Thai
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.2
rounded:
  sm: 10px
  md: 14px
  lg: 20px
  pill: 999px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#FFFFFF"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    height: 56px
  button-secondary:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text-primary}"
    borderColor: "{colors.hairline}"
    rounded: "{rounded.md}"
    height: 56px
  card:
    backgroundColor: "{colors.background}"
    rounded: "{rounded.lg}"
    shadow: "0 4px 16px rgba(29,35,48,0.06)"
  emergency-hero:
    background: "linear-gradient(135deg, #FF8A3D, #F26B1D, #E0500C)"
    textColor: "#FFFFFF"
    rounded: "{rounded.lg}"
  category-icon-tile:
    backgroundColor: "{colors.surface}"
    size: 64px
    rounded: 18px
    icon: "PNG 3D ต่อหมวด (ดู categoryIconAsset ใน fixgo_core)"
    typography: "{typography.label}"
---

## Overview

FixGo คือแอปเรียกช่างซ่อมรถฉุกเฉิน (Flutter, iOS/Android) ผู้ใช้ส่วนใหญ่ไม่มีความรู้เรื่องรถ และมักเปิดแอปตอนเครียด ดีไซน์ทั้งหมดจึงยึดหลัก **"เข้าใจง่ายและกดได้เร็วที่สุด"**

มี 2 แอปที่ใช้ design system เดียวกันผ่าน `packages/fixgo_core/lib/src/theme.dart`:
- **แอปลูกค้า (FixGo)**: ส่วนหัวโทนส้ม
- **แอปช่าง (FixGo ช่าง)**: ส่วนหัวโทนเข้ม (`navy`) เพื่อให้แยกได้ทันทีว่ากำลังเปิดแอปไหน ส่วนอื่นใช้ token ชุดเดียวกัน

**ประวัติการเปลี่ยนโทน**: navy+เหลือง → ม่วง+ทอง → BMW น้ำเงิน มุมเหลี่ยม → **เวอร์ชันปัจจุบัน**: ส้ม มุมโค้ง พื้นสว่าง ตามภาพอ้างอิงที่ผู้ใช้เลือก ชื่อตัวแปร Dart (`FixGoColors.navy`, `FixGoColors.accent`) คงเดิมทุกเวอร์ชัน

## Colors

- `accent` (`#F26B1D`) ส้ม FixGo ใช้กับปุ่ม action, สถานะที่กำลังดำเนินอยู่ และแท็บที่เลือก ตัวหนังสือบนส้มเป็นสีขาวเสมอ
- `accent-soft` (`#FFF1E7`) ใช้เป็นพื้นหลังไอคอนวงกลม chip และ indicator ของ bottom nav
- `navy` (`#1D2330`) คือสีหมึก ใช้กับหัวข้อ ตัวเลขราคา การ์ดพื้นเข้ม (แบนเนอร์, กระเป๋าเงินช่าง) และส่วนหัวของแอปช่าง
- `surface` (`#F5F6F8`) เป็นพื้นหลังของ Scaffold ส่วน `background` (ขาว) เป็นพื้นของการ์ด
- `success` / `warning` / `error` ใช้เฉพาะสถานะ (ดู `OrderStatusChip`) และปุ่มโทรหาช่าง (เขียว = โทร ตามความคุ้นเคยของผู้ใช้)

## Typography

ฟอนต์ **Noto Sans Thai** มีไฟล์ static ครบ 5 น้ำหนัก (400/500/600/700/800) ซึ่ง instance มาจาก variable font ของ Google Fonts จึงมีตัวอักษรละตินและตัวเลขในไฟล์เดียว (สัญญาอนุญาต OFL อยู่ที่ `assets/fonts/OFL.txt`)

**ต้องมีไฟล์ทุกน้ำหนักที่ใช้**: ถ้าขาด Flutter จะสังเคราะห์ตัวหนาเอง (faux bold) ทำให้สระและวรรณยุกต์ไทยหนาไม่เท่ากัน ดูแตก ซึ่งเป็นสาเหตุที่ตัวหนังสือเวอร์ชันก่อนดูไม่เรียบร้อย

ราคาต้องใช้ขนาดตั้งแต่ 24px น้ำหนัก 800 ขึ้นไปเสมอ

## Layout

- หน้าแรกของลูกค้าเป็นแบบ **bento**: การ์ด "เรียกช่างฉุกเฉิน" ใหญ่ที่สุดอยู่ซ้ายบน (กดแล้วเข้า wizard ทันที ไม่ต้องเลือกหมวดก่อน) ด้านขวาเป็นทางลัด 2 ใบ (รถสไลด์, แบตหมด) ถัดลงมาเป็นแบนเนอร์จุดขายแบบเลื่อนได้ และกริดหมวดบริการ 4 คอลัมน์
- Spacing ใช้ scale `xs`–`xl` เท่านั้น
- ทุก flow ที่มีหลายขั้นตอนต้องมี `StepProgress`
- Bottom navigation มี 4 แท็บคงที่ทั้ง 2 แอป

## Elevation & Shapes

- การ์ดใช้เงานุ่ม (`fixGoCardShadow`) แทน Material elevation ส่วนการ์ดในลิสต์ใช้เส้นขอบ `hairline`
- มุมโค้ง: การ์ด 20, ปุ่มและช่องกรอก 14, chip/badge แบบ pill
- ปุ่มฉุกเฉินและการ์ด hero มีเงาส้มจาง เพื่อดึงสายตาเป็นจุดแรก

## Icons

- ไอคอนหมวดบริการเป็น **3D** ทั้งชุด ต้องสื่อความหมายตรงกับบริการเสมอ
  - Microsoft Fluent Emoji (MIT): ช่างซ่อม (ค้อน+ประแจ), ระบบไฟ (สายฟ้า), แบต (แบตใกล้หมด), กุญแจ, ตรวจรถ (แว่นขยาย), ไซเรนฉุกเฉิน, ช่าง
  - วาดขึ้นใหม่สำหรับ FixGo: `tow.png` (รถสไลด์บรรทุกรถ) และ `tire.png` (ยางรถยนต์ล้อแม็ก) เพราะ Fluent ไม่มีภาพที่ตรงความหมาย (เวอร์ชันก่อนใช้รถส่งของและล้อเกวียน ผู้ใช้จึงเข้าใจผิด)
- ไอคอนต้องมีข้อความกำกับเสมอ
- **โลโก้**: หมุดตำแหน่งสีขาว + ประแจ บนพื้นส้มไล่สี (แอปช่างใช้พื้นเข้ม) ไฟล์ Android (legacy + adaptive), iOS AppIcon, splash และ web icon สร้างจากต้นฉบับเดียวกัน

## Do's and Don'ts

**Do**
- ใช้ส้มกับปุ่มหลักของหน้าเพียงปุ่มเดียว ปุ่มรองใช้ `FixGoSecondaryButton`
- ใช้ไอคอน 3D ที่สื่อความหมายตรง พร้อม label
- แสดงราคาตัวใหญ่ชัดเจนทุกครั้ง

**Don't**
- อย่าใช้โลโก้ ภาพ หรือข้อความโฆษณาของแบรนด์อื่น แม้จะใช้เลย์เอาต์คล้ายกัน
- อย่าเพิ่มน้ำหนักฟอนต์ที่ไม่มีไฟล์จริงใน `pubspec.yaml`
- อย่าเพิ่มสีนอก token ถ้าจำเป็นให้เพิ่มใน DESIGN.md ก่อนแล้วค่อย implement ใน `theme.dart`
