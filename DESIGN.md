---
version: alpha
name: FixGo
description: >
  Design system ของแอป FixGo — เรียกช่างซ่อมรถฉุกเฉิน กลุ่มเป้าหมายไม่มีความรู้เรื่องรถ
  โทนสีอิงจาก BMW corporate design system เต็มรูปแบบ (น้ำเงิน #1c69d4 + พื้นขาว
  + มุมเหลี่ยมคมทุกจุด ไม่มีมุมมนเลย) เลือกเพราะให้ความรู้สึกมั่นคง เป็นทางการ
  น่าเชื่อถือ อ่านง่ายแม้ใช้งานตอนเครียด (รถเสีย กลางคืน กลางแดด) — ผ่านการทดลอง
  โทนม่วง+ทอง (Glenfiddich) มาก่อน แต่ผู้ใช้ตัดสินใจสุดท้ายให้ใช้ BMW เต็มรูปแบบ
colors:
  navy: "#1A2129"
  # primary คือ alias มาตรฐานที่เครื่องมือแปลง (Figma/Tailwind) มองหา
  # เก็บ navy ไว้เป็นชื่อหลักเพราะโค้ด Dart (FixGoColors.navy) ผูกกับชื่อนี้อยู่แล้ว
  primary: "{colors.navy}"
  accent: "#1C69D4"
  accent-active: "#0653B6"
  background: "#FFFFFF"
  surface: "#F7F7F7"
  text-primary: "#262626"
  text-secondary: "#6B6B6B"
  success: "#22C55E"
  warning: "#F59E0B"
  error: "#DC2626"
  hairline: "#E6E6E6"
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
    fontFamily: Inter
    fontSize: 24px
    fontWeight: 900
    lineHeight: 1.2
  app-bar-title:
    fontFamily: Noto Sans Thai
    fontSize: 18px
    fontWeight: 700
    lineHeight: 1.2
  button:
    fontFamily: Noto Sans Thai
    fontSize: 17px
    fontWeight: 700
    lineHeight: 1.2
  button-secondary:
    fontFamily: Noto Sans Thai
    fontSize: 16px
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
  none: 0px
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
    rounded: "{rounded.none}"
    padding: 16px
  button-secondary:
    backgroundColor: transparent
    textColor: "{colors.text-primary}"
    borderColor: "{colors.text-primary}"
    typography: "{typography.button-secondary}"
    rounded: "{rounded.none}"
    padding: 16px
  card:
    backgroundColor: "{colors.background}"
    borderColor: "{colors.hairline}"
    rounded: "{rounded.none}"
    padding: "{spacing.md}"
  category-icon-tile:
    # ไอคอน 3D จาก Microsoft Fluent Emoji (MIT License) — รูปมีสีในตัวเองอยู่แล้ว
    # ไม่ต้องมีพื้นหลังสีคลุม ต่างจากเวอร์ชันก่อนที่ใช้ Material icon + tint พื้นหลัง
    # ที่มา: github.com/microsoft/fluentui-emoji
    # สัญญาอนุญาตเต็ม: assets/icons/licenses/fluentui-emoji-LICENSE.txt
    backgroundColor: transparent
    icon: "รูป PNG 3D ต่อหมวด (ดู categoryIconAsset ใน fixgo_core)"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
  badge-recommended:
    backgroundColor: "{colors.accent}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
---

## Overview

FixGo คือแอปเรียกช่างซ่อมรถฉุกเฉิน (Flutter, iOS/Android) กลุ่มผู้ใช้หลักคือคนที่ไม่มีความรู้เรื่องรถและมักใช้งานตอนเครียด (รถเสียกลางทาง) ดีไซน์ทั้งหมดจึงยึดหลัก **"เข้าใจง่ายที่สุด"** เหนือความสวยงามที่ซับซ้อน

โทนภาพอ้างอิงจาก **BMW corporate design system** เต็มรูปแบบ — น้ำเงิน BMW (`#1c69d4`) บนพื้นขาว มุมเหลี่ยมคมทุกจุด ไม่มีมุมมนเลยทั้งระบบ ให้ความรู้สึกมั่นคง เป็นทางการ น่าเชื่อถือ ต่างจากคู่แข่งกลุ่ม on-demand service ในไทยที่มักใช้โทนส้ม-เหลือง มุมโค้งมนกันหมด (24CarFix เป็นตัวอย่าง)

**ประวัติการเปลี่ยนโทน**: เวอร์ชันแรกใช้ navy+เหลือง (อิง Antixor Taxi) → เปลี่ยนเป็นม่วงเข้ม+ทอง (อิงกล่อง Glenfiddich 15 ปี) → เวอร์ชันปัจจุบันเปลี่ยนเป็น BMW เต็มรูปแบบตามการตัดสินใจสุดท้ายของผู้ใช้ ชื่อตัวแปรในโค้ด Dart (`FixGoColors.navy`, `FixGoColors.accent`) ยังคงเดิมทุกเวอร์ชันเพื่อไม่ต้องแก้ทุกไฟล์ที่อ้างอิง มีแค่ค่า hex ที่เปลี่ยน

มี 2 แอปที่ใช้ design system เดียวกัน: **Customer App** (ลูกค้าเรียกช่าง) และ **Provider App / FixGo Fixer** (ช่างรับงาน) — implement อยู่ใน `packages/fixgo_core/lib/src/theme.dart`

## Colors

- `primary` เป็น alias ชี้ไปที่ `navy` (`#1A2129`) — เครื่องมือแปลง token ภายนอก (Figma/Tailwind) มองหาชื่อ `primary` เป็นมาตรฐาน โค้ด Dart จริงยังเรียกผ่านชื่อ `navy`
- `navy` (`#1A2129`) คือพื้นหลังเข้ม (BMW surface-dark) ใช้กับหน้า login, hero card, กระเป๋าเงินช่าง — ไม่ใช่สีข้อความ
- `accent` (`#1C69D4`) น้ำเงิน BMW **ใช้กับปุ่มสำคัญเท่านั้น** — กฎตายตัวคือทั้งแอปมีปุ่มสีน้ำเงินแบบเดียว ไม่มีปุ่มสีอื่นแข่งความสนใจในหน้าเดียวกัน ตัวหนังสือบนปุ่มเป็นสีขาวเสมอ (ไม่ใช่ navy เหมือนเวอร์ชันก่อน เพราะน้ำเงินเข้มพอที่จะต้องใช้ขาวถึงจะอ่านชัด)
- `text-primary` (`#262626`, ink) แยกจาก `navy` ชัดเจน — ใช้กับตัวหนังสือบนพื้นขาว ไม่ใช่สีเดียวกับพื้นหลังเข้มเหมือนเวอร์ชันก่อน
- `success` / `warning` / `error` ใช้เฉพาะสถานะ (เช่น badge สถานะออเดอร์) ห้ามใช้กับปุ่ม action
- ไอคอนหมวดบริการ (category-icon-tile) ใช้รูป 3D จาก Microsoft Fluent Emoji (MIT License) แทน Material icon แบน — มีสีสันในตัวรูปอยู่แล้ว ไม่ต้องคุมด้วย color token ดู mapping เต็มใน `fixgo_core` ฟังก์ชัน `categoryIconAsset`

## Typography

Font หลัก **Noto Sans Thai** (รองรับไทย+อังกฤษ อ่านง่ายบนมือถือ ฟรีเชิงพาณิชย์) ยกเว้นตัวเลขราคาที่ใช้ **Inter** เพราะตัวเลขอ่านง่ายกว่าเมื่อ font ออกแบบมาสำหรับตัวเลขโดยเฉพาะ

**ข้อจำกัดที่ต้องรู้**: BMW ต้นฉบับใช้ระบบ 2 น้ำหนัก (heavy 700 สำหรับ display + light 300 สำหรับ body) แต่ FixGo bundle มาแค่ font น้ำหนัก Regular (400) เดียว — ลองหาไฟล์ Light เพิ่มแล้วแต่ถูก network proxy บล็อกทั้ง GitHub และ jsdelivr ตอนนี้ body/caption ใช้ 400 ไปก่อน (ไม่ใช่ 300 ตาม BMW จริง) ถ้าต้องการความแท้จริงต้องหาไฟล์ font น้ำหนัก Light มา bundle เพิ่มในอนาคต

กฎสำคัญ: ราคาต้องใช้ `price` token เสมอ (ใหญ่ ตัวหนามาก) — ห้ามลดขนาด/น้ำหนักแม้ในพื้นที่จำกัด เพราะราคาเป็นข้อมูลที่ผู้ใช้ต้องเห็นชัดที่สุดก่อนตัดสินใจกดยืนยัน

Token ครบ 10 ระดับ: `headline` (หัวข้อใหญ่), `app-bar-title` (แถบด้านบนของหน้า), `title` (หัวข้อรอง/การ์ด), `body` (เนื้อหาทั่วไป), `caption` (คำอธิบายรอง), `price` (ราคา), `button` / `button-secondary` (ตัวหนังสือบนปุ่มหลัก/รอง), `label` (label ใต้ไอคอน/badge), `nav-label` (ข้อความ bottom nav)

## Layout

- Spacing ใช้ scale จาก `spacing.xs` ถึง `spacing.xl` เท่านั้น ห้ามใช้ค่าตัวเลขอิสระ
- Booking wizard และ flow อื่นที่มีหลายขั้นตอน **ต้องมี progress indicator เสมอ** (ดู `StepProgress` widget) ผู้ใช้ต้องเห็นตลอดว่าอยู่ขั้นไหน เหลืออีกกี่ขั้น
- Bottom navigation คงที่ 4 แท็บทั้ง 2 แอป ไม่ใช้ hamburger menu หรือ drawer ซ่อนเมนูหลัก

## Elevation & Depth

FixGo ไม่ใช้เงาเลยทั้งระบบ (ต่างจากเวอร์ชันก่อนที่มีเงาบางบนการ์ดหมวดบริการ) — แยกพื้นที่ด้วย `border` สีเทาอ่อน (`hairline`) แทนเงาทุกจุด ตรงตามแนวทาง flat design ของ BMW ที่ไม่ใช้ elevation เพื่อสร้างมิติ แต่ใช้เส้นขอบและช่องว่างแทน

ไม่มี elevation level ใดๆ เลย ทุก component อยู่บนระนาบเดียวกัน (`elevation: 0` ทุกจุดใน `theme.dart`)

## Shapes

**ใช้มุมเหลี่ยมคม (`rounded.none`, 0px) ทุกจุดในระบบ ไม่มีมุมมนเลย** — ปุ่ม, การ์ด, ช่องกรอกข้อมูล, ไอคอนหมวดบริการ, badge ทั้งหมดเป็นสี่เหลี่ยมคมชัด ตรงตามดีไซน์ BMW ต้นฉบับที่ใช้ `rounded.none` กับทุก component โดยไม่มีข้อยกเว้น สื่อความรู้สึกมั่นคง เป็นทางการ ต่างจากเวอร์ชันก่อนที่ใช้มุมมน/pill สื่อความเป็นมิตร

## Components

- **button-primary**: ปุ่มเดียวที่ใช้สั่งการสำคัญ (ยืนยันเรียกช่าง, รับงาน, ขอเบิกเงิน) พื้นน้ำเงิน ตัวหนังสือขาวเสมอ มุมเหลี่ยมคม
- **button-secondary**: ใช้กับ action รอง (ยกเลิก, ปฏิเสธงาน) ขอบสี ink (`text-primary`) พื้นขาว มุมเหลี่ยมคม ป้องกันไม่ให้แย่งความสนใจจาก primary
- **category-icon-tile**: ไอคอน 3D สีสัน (Microsoft Fluent Emoji, MIT) วางตรงกลางการ์ด ไม่มีพื้นหลังสีคลุม **ต้องมี label ข้อความกำกับเสมอ** ห้ามใช้ไอคอนอย่างเดียวโดยไม่มีคำอธิบาย เพราะกลุ่มเป้าหมายไม่มีความรู้เรื่องรถ ตีความไอคอนเองไม่ได้
- **badge-recommended**: ใช้ระบุตัวเลือกแนะนำ (เช่น "เรียกช่างฉุกเฉิน" ในหน้าแรก) พื้นน้ำเงิน ตัวหนังสือขาว มีแค่ 1 badge ต่อหน้าจอ ป้องกันการเน้นเยอะเกินจนไม่มีจุดเด่น

## Do's and Don'ts

**Do**
- ใช้สีน้ำเงิน (`accent`) กับปุ่มสำคัญที่สุดของหน้านั้นเพียงปุ่มเดียว
- ใช้มุมเหลี่ยมคม (`rounded.none`) กับทุก component ไม่มีข้อยกเว้น
- แสดงราคาด้วย `price` token ทุกครั้งที่มีตัวเลขเงินปรากฏ
- ใส่ label ข้อความกำกับไอคอนทุกจุด
- แสดง progress indicator ในทุก flow ที่มีมากกว่า 1 ขั้นตอน

**Don't**
- อย่าใช้สีน้ำเงินกับมากกว่า 1 ปุ่มในหน้าเดียวกัน
- อย่าใส่มุมมนหรือเงากลับเข้ามาที่จุดไหนเลย (ขัดกับดีไซน์ BMW ที่ตั้งใจเลือก)
- อย่าลดขนาด/น้ำหนักตัวอักษรของราคาต่ำกว่า `price` token
- อย่าใช้ไอคอนเดี่ยวๆ โดยไม่มีข้อความกำกับ
- อย่าเพิ่มสีใหม่นอกเหนือจาก token ที่กำหนดไว้ — ถ้าจำเป็นต้องมีสีใหม่ ให้เพิ่ม token ใน DESIGN.md นี้ก่อน แล้วค่อย implement ใน `theme.dart`
