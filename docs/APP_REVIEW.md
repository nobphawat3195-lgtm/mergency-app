# เตรียมส่งแอปเข้า App Store / Google Play

เอกสารนี้สรุปสิ่งที่ระบบมีให้แล้วสำหรับการรีวิวของ Apple และ Google และสิ่งที่ต้องทำเองก่อนส่ง

## 1. บัญชีทดสอบสำหรับทีมรีวิว

ทีมรีวิวรับ SMS ไม่ได้ จึงต้องมีเบอร์ที่ใช้รหัส OTP ตายตัว

1. เลือกเบอร์ที่ไม่มีเจ้าของจริง 2 เบอร์ (ลูกค้า 1, ช่าง 1) เช่น `0800000001`, `0800000002`
2. ตั้งค่าใน `.env` ของเซิร์ฟเวอร์จริง
   ```
   REVIEW_LOGIN_PHONES="0800000001,0800000002"
   REVIEW_LOGIN_CODE="xxxxxx"   # ตัวเลข 6 หลัก ห้ามใช้ 123456
   ```
   เบอร์ในรายการจะไม่ถูกส่ง SMS และไม่ติดเวลารอ 60 วินาที
3. สร้างบัญชีช่างที่อนุมัติแล้วให้เบอร์ช่าง
   ```
   REVIEW_PROVIDER_PHONE=0800000002 npm run seed:review
   ```
4. กรอกใน App Store Connect > App Review Information > Sign-in required
   - แอป FixGo: เบอร์ `0800000001` รหัส `xxxxxx`
   - แอป FixGo Fixer: เบอร์ `0800000002` รหัส `xxxxxx` (บัญชีช่างที่อนุมัติแล้ว เปิดสวิตช์ "พร้อมรับงาน" เพื่อรับงาน)
5. หลังรีวิวผ่าน ลบเบอร์ออกจาก `REVIEW_LOGIN_PHONES` หรือเปลี่ยนรหัส

## 2. ลิงก์ที่ต้องกรอกใน store

หน้าเว็บเหล่านี้ให้บริการโดย backend (สาธารณะ ไม่ต้องล็อกอิน)

| ช่องใน store | ลิงก์ |
|---|---|
| Privacy Policy URL | `https://<api-domain>/api/legal/privacy` |
| Terms / EULA (ถ้าต้องการ) | `https://<api-domain>/api/legal/terms` |
| Support URL | `https://<api-domain>/api/legal/support` |
| Google Play: ลิงก์ขอลบบัญชี | `https://<api-domain>/api/legal/delete-account` |

ตั้งข้อมูลบริษัทใน `.env` ก่อน ไม่งั้นหน้าเว็บจะแสดงช่องสีเหลือง `[ชื่อบริษัท]`
```
LEGAL_COMPANY_NAME="..."
LEGAL_CONTACT_EMAIL="..."
LEGAL_CONTACT_PHONE="..."
LEGAL_ADDRESS="..."
LEGAL_UPDATED_AT="..."
```
เนื้อหาอยู่ที่ `backend/src/legal/content.ts` เป็นฉบับร่างที่เขียนตามการทำงานจริงของระบบ **ต้องให้นักกฎหมายตรวจก่อนใช้จริง**

## 3. การลบบัญชี (App Store Guideline 5.1.1(v))

- ในแอปทั้งสอง: แท็บ โปรไฟล์ > ลบบัญชี
- API: `DELETE /api/account`
- เงื่อนไขก่อนลบ: ไม่มีงานที่ยังไม่จบ, ลูกค้าไม่มีงานที่ยังไม่ชำระ, ช่างไม่มียอดคงเหลือหรือคำขอเบิกที่รอโอน
- ลบ/ปิดบังเบอร์ ชื่อ ที่อยู่ หมายเหตุ รูป ความเห็น ข้อมูลผู้ขาย รูปเครื่องมือ และบัญชีรับเงิน
  เก็บตัวเลขธุรกรรมไว้ตามกฎหมายบัญชี โทเคนเดิมใช้ไม่ได้ทันที เบอร์เดิมสมัครใหม่ได้เป็นบัญชีใหม่

## 4. App Privacy (หน้า "App Privacy" ใน App Store Connect)

ต้องตรงกับ `ios/Runner/PrivacyInfo.xcprivacy` ของแต่ละแอป: ไม่มี tracking ทุกข้อใช้เพื่อ App Functionality และผูกกับตัวผู้ใช้

| ข้อมูล | FixGo | FixGo Fixer |
|---|:-:|:-:|
| Phone Number | ✓ | ✓ |
| Precise Location | ✓ | ✓ |
| Photos | ✓ | ✓ |
| Other User Content (หมายเหตุ รายงานตรวจรถ) | ✓ | ✓ |
| Purchase History (ประวัติงานและการชำระ) | ✓ | ✓ |
| User ID | ✓ | ✓ |
| Name | | ✓ |
| Other Financial Info (บัญชีรับเงิน) | | ✓ |

## 5. สิ่งที่ยังต้องทำเองก่อนส่ง

- สมัคร Apple Developer Program และลงทะเบียน Bundle ID `com.fixgo.fixgoCustomer`, `com.fixgo.fixgoProvider`
- Build และเซ็นแอปบน Mac ที่มี Xcode (หรือบริการ build บนคลาวด์) แล้วทดสอบผ่าน TestFlight บน iPhone จริง
- เซิร์ฟเวอร์จริงพร้อม HTTPS, SMS จริง, ที่เก็บรูป และระบบรับชำระเงินจริง
- ภาพหน้าจอ iPhone 6.9 นิ้ว คำอธิบายแอป หมวดหมู่ และอายุผู้ใช้
