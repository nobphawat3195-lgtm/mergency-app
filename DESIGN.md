---
version: beta
name: FixGo
description: >
  Design system ของแอป FixGo (ลูกค้า) และ FixGo Fixer (ช่าง) — เรียกช่างซ่อมรถฉุกเฉิน 24 ชม.
  กลุ่มเป้าหมายไม่มีความรู้เรื่องรถและมักเปิดแอปตอนเครียด โทนเขียว (ปลอดภัย พร้อมช่วยเหลือ)
  พื้นมิ้นต์อ่อน การ์ดขาวมุมโค้ง เขียวเข้มเป็นสีของทุก action ปุ่มเรียกช่างด่วนเด่นที่สุดบนจอ
colors:
  ink: "#122821"          # FixGoColors.navy / textPrimary
  primary: "{colors.accent}"
  accent: "#0B5F45"       # เขียวเข้ม ปุ่มหลัก
  accent-active: "#084A36"
  jade: "#16A37B"         # เขียวหยก ไอคอน เส้น ขอบเน้น (ห้ามเป็นตัวอักษรเล็กบนขาว)
  lime: "#C7EE77"         # สีเน้น badge/ปุ่มรองบนพื้นเข้ม คู่กับตัวอักษร ink
  accent-soft: "#ECF8F1"  # มิ้นต์ chip/พื้นไอคอน
  background: "#FFFFFF"
  surface: "#ECF8F1"      # พื้น Scaffold
  text-primary: "#122821"
  text-secondary: "#4A6259"
  success: "#0E7A57"
  warning: "#9A5B00"
  error: "#C62828"
  hairline: "#D5E8DE"
  disabled-bg: "#E3EBE7"
  disabled-fg: "#5F7A70"
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
    textColor: "{colors.accent}"
    borderColor: "{colors.accent}"
    rounded: "{rounded.md}"
    height: 56px
  button-emergency:
    background: "linear-gradient(135deg, #0B5F45, #084A36)"
    textColor: "#FFFFFF"
    height: 64px
    rounded: "{rounded.pill}"
    leading: "วงกลมขาว 48px + ไอคอนโทรศัพท์"
  card:
    backgroundColor: "{colors.background}"
    rounded: "{rounded.lg}"
    shadow: "0 4px 16px rgba(18,40,33,0.08)"
  hero-banner:
    image: "apps/customer/assets/images/home_hero.jpg (1672x941 ไม่มีข้อความในภาพ)"
    aspectRatio: "1672 / 941 — ห้ามครอบ ใบหน้าและรถต้องเห็นครบ"
    text: "วาดด้วย Flutter บนพื้นเขียวฝั่งซ้าย กว้างไม่เกิน 47%"
  category-icon-tile:
    backgroundColor: "{colors.surface}"
    size: 64px
    rounded: 18px
    icon: "PNG 3D ต่อหมวด (ดู categoryIconAsset ใน fixgo_core)"
    typography: "{typography.label}"
---

## Overview

FixGo คือแอปเรียกช่างซ่อมรถฉุกเฉิน (Flutter, iOS/Android) ผู้ใช้ส่วนใหญ่ไม่มีความรู้เรื่องรถและมักเปิดแอปตอนเครียด ดีไซน์ยึดหลัก **"เข้าใจง่ายและกดได้เร็วที่สุด"**

2 แอปใช้ design system เดียวกันผ่าน `packages/fixgo_core/lib/src/theme.dart`:
- **FixGo (ลูกค้า)**: หัวเขียวเข้ม `fixGoBrandGradient` โลโก้พื้น `#0B5F45`
- **FixGo Fixer (ช่าง)**: หัวไล่จากหมึก `#122821` ไปเขียวเข้ม โลโก้พื้น `#122821` ประแจสีมะนาว และคำว่า "Fixer" สีมะนาว ให้แยกออกทันทีว่าเป็นแอปช่าง

**ประวัติการเปลี่ยนโทน**: navy+เหลือง → ม่วง+ทอง → น้ำเงิน → ส้มสว่าง → **ปัจจุบัน: เขียว** ตาม concept ของเจ้าของโปรเจกต์ ชื่อตัวแปร Dart (`FixGoColors.navy`, `FixGoColors.accent`) คงเดิมทุกเวอร์ชัน

## Colors

| token | ค่า | ใช้กับ |
|---|---|---|
| `accent` | `#0B5F45` | ปุ่มหลัก แท็บที่เลือก สถานะกำลังทำ ตัวอักษรบนพื้นนี้เป็นขาวเสมอ |
| `accentActive` | `#084A36` | ปลาย gradient และสถานะกด |
| `jade` | `#16A37B` | ไอคอนเช็ก สวิตช์เปิด เส้นเน้น (ตัวอักษรขาวบน jade ได้เฉพาะตัวใหญ่) |
| `lime` | `#C7EE77` | ป้ายราคา ปุ่มรองบนพื้นเข้ม ตัวอักษรบนพื้นนี้ใช้ `ink` |
| `accentSoft`/`surface` | `#ECF8F1` | พื้นหน้าจอ chip พื้นไอคอน indicator ของ bottom nav |
| `navy`/`textPrimary` | `#122821` | หัวข้อ ตัวเลข การ์ดเข้มฝั่งช่าง |
| `textSecondary` | `#4A6259` | คำอธิบาย |

### Contrast (WCAG 2.1) ที่ตรวจแล้ว

| คู่สี | อัตราส่วน | ผล |
|---|---|---|
| ขาว บน `#0B5F45` (ปุ่มหลัก) | 7.67 | AAA |
| ขาว บน `#084A36` | 10.28 | AAA |
| `#122821` บน `#C7EE77` (ป้ายราคา) | 11.79 | AAA |
| `#C7EE77` บน `#0B5F45` | 5.82 | AA |
| `#122821` บน `#ECF8F1` | 14.26 | AAA |
| `#4A6259` บน `#ECF8F1` / ขาว | 6.05 / 6.60 | AA |
| `#0B5F45` บน `#ECF8F1` (ลิงก์/แท็บ) | 7.04 | AAA |
| success `#0E7A57` / warning `#9A5B00` / error `#C62828` บนขาว | 5.33 / 5.43 / 5.62 | AA |
| `#122821` บน `#FFF4DC` (แถบรอยืนยันยอดเงิน) | 14.23 | AAA |
| ปุ่ม disabled `#5F7A70` บน `#E3EBE7` | 3.84 | ผ่านเกณฑ์ UI 3:1 (ปุ่มที่กดไม่ได้ WCAG ไม่บังคับ 4.5) |
| ขาว บน `#16A37B` | 3.20 | ใช้ได้เฉพาะตัวใหญ่/ไอคอน ห้ามใช้กับข้อความเล็ก |

## Typography

ฟอนต์ **Noto Sans Thai** มีไฟล์ static ครบ 5 น้ำหนัก (400/500/600/700/800) ซึ่ง instance มาจาก variable font ของ Google Fonts จึงมีตัวอักษรละตินและตัวเลขในไฟล์เดียว (สัญญาอนุญาต OFL อยู่ที่ `assets/fonts/OFL.txt`)

**ต้องมีไฟล์ทุกน้ำหนักที่ใช้**: ถ้าขาด Flutter จะสังเคราะห์ตัวหนาเอง (faux bold) ทำให้สระและวรรณยุกต์ไทยหนาไม่เท่ากัน ดูแตก ซึ่งเป็นสาเหตุที่ตัวหนังสือเวอร์ชันก่อนดูไม่เรียบร้อย

ราคาต้องใช้ขนาดตั้งแต่ 24px น้ำหนัก 800 ขึ้นไปเสมอ

## Layout

### หน้าแรกลูกค้า (ตาม concept สีเขียว)
1. หัวเขียวเข้ม: โลโก้ FixGo + pill ตำแหน่งปัจจุบัน (ข้อมูลจริงจาก GPS แตะเพื่อหาใหม่)
2. **การ์ดเรียกช่างด่วน** ลอยทับหัว: หัวข้อ 32px + ปุ่ม 64px เต็มความกว้าง เป็นองค์ประกอบที่เด่นที่สุดบนจอ
3. แบนเนอร์ภาพจริง (ภาพไม่มีข้อความ) ข้อความและปุ่ม "ดูขั้นตอนบริการ" วาดด้วย Flutter
4. บริการยอดนิยม 4 ช่อง: ช่างซ่อมรถ, จั๊มแบต (เข้าขั้นเลือกประเภทรถทันที), ยางรั่ว, รถยก
5. การ์ดตรวจรถมือสอง: ราคาและจำนวนรายการดึงจาก API เสมอ
6. หมวดบริการทั้งหมด (ปุ่ม "ดูทั้งหมด" เลื่อนลงมาที่นี่)

### หน้าแรกช่าง (FixGo Fixer)
1. หัวเข้ม + สวิตช์ "พร้อมรับงาน" (อ่านสถานะจริงจาก backend ตอนเปิด)
2. งานเข้ามาใหม่: นับถอยหลัง ระยะทาง ที่อยู่ ราคาประเมิน ปุ่มรับงาน/ปฏิเสธ
3. ความคืบหน้างาน 4 ขั้น: รับงาน → เดินทาง → กำลังซ่อม → ปิดงาน (ตรงกับสถานะที่ลูกค้าเห็น)
4. สรุปวันนี้: งานเสร็จ (completedAt วันนี้), รายได้ที่ยืนยันแล้ว (ORDER_EARNING วันนี้), ยอดถอนได้
5. เมนูหลัก: งานของฉัน, กระเป๋าเงิน, โปรไฟล์

ไม่มี "เวลาออนไลน์" เพราะ backend ยังไม่เก็บข้อมูลนี้ ห้ามแสดงตัวเลขสมมติ

### ทั่วไป
- Spacing ใช้ scale `xs`–`xl` เท่านั้น
- ทุก flow หลายขั้นตอนต้องมี `StepProgress`
- Bottom navigation 4 แท็บคงที่ทั้ง 2 แอป

## Elevation & Shapes

- การ์ดใช้เงานุ่ม (`fixGoCardShadow`) การ์ดในลิสต์ใช้เส้นขอบ `hairline`
- การ์ดที่กดได้ให้ใช้ `DecoratedBox(shadow)` → `Material(borderRadius, clip)` → `InkWell` ห้ามใส่ `boxShadow` ใน `Ink` ใต้ `Material` สีโปร่ง (เงาจะรั่วเป็นสี่เหลี่ยมเทาที่มุม)
- มุมโค้ง: การ์ด 20, ปุ่มและช่องกรอก 14, ปุ่มฉุกเฉินและ chip แบบ pill

## Icons & Logo

- ไอคอนหมวดบริการเป็น 3D ชุดที่เจ้าของโปรเจกต์จัดให้ ต้องมีข้อความกำกับเสมอ
- **โลโก้**: รถ + ประแจ + "24" มุมขวาบน ต้นฉบับแก้ไขได้ที่ `tool/brand/fixgo_logo.svg` และ `tool/brand/fixgo_fixer_logo.svg`
- สร้างไอคอนทุกแพลตฟอร์มด้วย `tool/brand/render_icons.mjs` (Playwright/Chromium) แล้วย่อเป็น Android mipmap/adaptive, iOS AppIcon/LaunchImage, web icons
- Splash: Android `values/colors.xml` (`splash_background`) และ iOS `LaunchScreen.storyboard` ใช้สีพื้นโลโก้ของแต่ละแอป

## Data honesty rules

- ภาพ mockup เป็นแนวทางด้านภาพเท่านั้น ห้ามนำข้อความ/ตัวเลขในภาพไปแสดงเป็นข้อมูลจริง (เช่น "ทั่วไทย", "200+ จุด", "เริ่มต้น 1,500")
- ราคา จำนวนรายการตรวจ รายได้ และจำนวนงาน ต้องมาจาก API เท่านั้น
- การชำระเงินเป็น "ชำระแล้ว" ได้เมื่อ backend บันทึก `PAID` จาก webhook ผู้ให้บริการรับชำระที่ตรวจสอบแล้วเท่านั้น การแสดง QR หรือการกดปุ่มไม่เปลี่ยนสถานะ แสดง "รอยืนยันยอดเงิน" ระหว่างนั้น
- ข้อมูลที่ยังตรวจสอบต้นฉบับไม่ได้ (TRUSTCAR 360) แสดงเป็น "ต้นแบบ" และไม่เปิดจอง

## Do's and Don'ts

**Do**
- ใช้เขียวเข้มกับปุ่มหลักของหน้าเพียงปุ่มเดียว ปุ่มรองใช้ outline
- ใช้ `lime` คู่กับตัวอักษร `ink` เท่านั้น
- แสดงราคาตัวใหญ่ชัดเจนทุกครั้ง

**Don't**
- อย่าใช้โลโก้ ภาพ หรือข้อความโฆษณาของแบรนด์อื่น
- อย่าเพิ่มน้ำหนักฟอนต์ที่ไม่มีไฟล์จริงใน `pubspec.yaml`
- อย่าเพิ่มสีนอก token ถ้าจำเป็นให้เพิ่มใน DESIGN.md ก่อนแล้วค่อย implement ใน `theme.dart`
