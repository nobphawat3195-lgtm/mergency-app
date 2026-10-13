# Push notification (FCM)

ทั้งสองแอปใช้ Firebase Cloud Messaging ส่งแจ้งเตือนทั้ง Android และ iOS โดย iOS ส่งผ่าน APNs key ที่อัปโหลดไว้ใน Firebase

push เป็นแค่สัญญาณให้แอปไปดึงข้อมูลใหม่ สถานะจริงมาจาก API เสมอ ถ้าส่ง push ไม่สำเร็จ งานยังเดินต่อได้ตามปกติ เพราะแอปยังดึงข้อมูลเป็นรอบอยู่

## เหตุการณ์ที่แจ้ง

| เหตุการณ์ | ผู้รับ | `type` |
|---|---|---|
| มีงานใหม่ในรัศมี | ช่างทุกคนในรอบเสนองาน | `OFFER` |
| หาช่างไม่ได้ | ลูกค้า | `NO_MATCH` |
| ช่างรับงาน / กำลังเดินทาง / เริ่มงาน | ลูกค้า | `MATCHED` / `EN_ROUTE` / `IN_PROGRESS` |
| ช่างเสนอราคา | ลูกค้า | `QUOTE_PROPOSED` |
| ลูกค้ายืนยัน / ไม่ยืนยันราคา | ช่าง | `QUOTE_APPROVED` / `QUOTE_REJECTED` |
| ปิดงาน (มียอดต้องชำระ) | ลูกค้า | `COMPLETED` |
| ลูกค้ายกเลิกงาน | ช่างที่รับงานไว้ | `CANCELLED` |
| ชำระพร้อมเพย์สำเร็จ (Stripe webhook) | ลูกค้าและช่าง | `PAID` |
| ช่างยืนยันรับเงินสด | ลูกค้า | `PAID` |

ทุกข้อความมี `data` เป็น `{ type, orderId, orderNo }` การทำงานเมื่อผู้ใช้แตะแจ้งเตือน:
- แอปลูกค้าเปิดหน้าติดตามงาน
- แอปช่างเปิดหน้าหลักถ้าเป็นงานใหม่ (`OFFER`) หรือหน้างานของฉันสำหรับเหตุการณ์อื่น

ถ้าได้รับแจ้งเตือนตอนเปิดแอปอยู่ แอปจะแสดงแถบแจ้งเตือนในแอปพร้อมปุ่ม "ดู" และดึงข้อมูลหน้านั้นใหม่ทันที

## ตั้งค่าครั้งแรก

1. สร้างโปรเจกต์ที่ [Firebase Console](https://console.firebase.google.com)
2. เพิ่มแอป 4 ตัว:
   - Android `com.fixgo.fixgo_customer`
   - Android `com.fixgo.fixgo_provider`
   - iOS ของแอปลูกค้า
   - iOS ของแอปช่าง

   ใช้ bundle id เดียวกับใน Xcode ไม่ต้องดาวน์โหลด `google-services.json` หรือ `GoogleService-Info.plist` เพราะแอปรับค่าผ่าน `--dart-define`
3. **APNs:** ที่ Apple Developer ไปที่ Keys แล้วสร้าง key ที่เปิด Apple Push Notifications service (APNs) ได้ไฟล์ `.p8` จากนั้นที่ Firebase ไปที่ Project settings > Cloud Messaging > Apple app configuration แล้วอัปโหลดไฟล์นี้ (ใส่ Key ID และ Team ID) ให้ทั้งสองแอป iOS
4. **Xcode:** ที่ target Runner ไปที่ Signing & Capabilities แล้วตรวจว่ามี **Push Notifications** และ **Background Modes > Remote notifications** ทั้งสองอย่างนี้ตั้งไว้ใน `Runner.entitlements` และ `Info.plist` แล้ว แต่ App ID ใน Apple Developer ต้องเปิด Push ด้วย
5. **Backend:** ที่ Firebase ไปที่ Project settings > Service accounts > Generate new private key แล้วใส่ค่าจากไฟล์ JSON ใน env ของเซิร์ฟเวอร์ (ห้าม commit ไฟล์ JSON)
   ```
   PUSH_PROVIDER=fcm
   FCM_PROJECT_ID=<project_id>
   FCM_CLIENT_EMAIL=<client_email>
   FCM_PRIVATE_KEY=<private_key>   # ใส่ \n แทนการขึ้นบรรทัดใหม่ได้
   ```
6. **Build แอป:** ค่าเหล่านี้ดูได้ที่ Project settings > General > Your apps ไม่ใช่ความลับ (มีอยู่ในแอปที่ติดตั้งอยู่แล้ว) แต่แยกตามแอป
   ```
   flutter build ipa \
     --dart-define=API_BASE_URL=https://api.example.com \
     --dart-define=FIREBASE_PROJECT_ID=... \
     --dart-define=FIREBASE_SENDER_ID=... \
     --dart-define=FIREBASE_API_KEY=... \
     --dart-define=FIREBASE_IOS_APP_ID=1:...:ios:... \
     --dart-define=FIREBASE_ANDROID_APP_ID=1:...:android:...
   ```
   ถ้าไม่ใส่ค่าเหล่านี้ push จะปิดทั้งหมด แต่แอปยังทำงานได้ปกติ

## การทำงาน

- `POST /api/devices` `{ token, platform: IOS|ANDROID }` แอปเรียกหลังล็อกอินและทุกครั้งที่เปิดแอป
  - ถ้าโทเคนเดิมถูกลงทะเบียนโดยบัญชีอื่น (เปลี่ยนบัญชีบนเครื่องเดิม) เจ้าของโทเคนจะย้ายมาเป็นบัญชีล่าสุด
- `DELETE /api/devices` `{ token }` แอปเรียกก่อนล็อกเอาต์
- ถ้า FCM ตอบว่าโทเคนใช้ไม่ได้แล้ว (เช่น ถอนแอป) backend จะลบโทเคนนั้นเอง
- ลบบัญชีแล้วโทเคนทุกเครื่องของบัญชีนั้นจะถูกลบด้วย
- Android สร้างช่องแจ้งเตือน `fixgo_updates` แบบความสำคัญสูง (เด้งบนจอพร้อมเสียง) ใน `MainActivity`
- ตอนพัฒนาใช้ `PUSH_PROVIDER=console` ข้อความจะถูกพิมพ์ลง log ของ backend แทนการส่งจริง

## ทดสอบบนเครื่องจริง

push ใช้กับ iOS Simulator ได้จำกัด ให้ทดสอบบน iPhone จริงผ่าน TestFlight และบน Android จริงหรือ emulator ที่มี Google Play

## แจ้งเตือนช่างผ่าน LINE (ใช้ก่อนมีแอปในสโตร์)

ระหว่างที่ช่างใช้เว็บแอป (`PUSH_PROVIDER=console`) เว็บเตือนได้เฉพาะตอนเปิดหน้าอยู่ จึงส่ง LINE จาก FixGo Official Account ไปหาช่างแทน:

| เหตุการณ์ | ข้อความ |
|---|---|
| `OFFER` งานใหม่ (ทุกช่างในรอบเสนองาน) | 🔔 มีงานใหม่ใกล้คุณ / บริการ · เขต / ราคาประเมิน / กดรับภายในกี่นาที |
| `QUOTE_APPROVED` / `QUOTE_REJECTED` | ลูกค้ายืนยัน / ไม่ยืนยันราคา |
| `CANCELLED` | งานถูกยกเลิก ไม่ต้องเดินทางต่อ |

- ทุกข้อความมีปุ่ม "เปิดรับงาน" ไปที่เว็บแอปช่าง (`https://<FIXER_DOMAIN>/`)
- ส่งเฉพาะช่างที่ล็อกอินด้วย LINE (มี LINE userId) และเพิ่มเพื่อน OA แล้ว
- ส่งแบบไม่รอผล: LINE ล่มหรือตอบ error งานยังเสนอ/ยกเลิกได้ตามปกติ ระบบแค่เขียน warn ลง log
- ข้อความมีแค่เขต/จังหวัด ไม่มีบ้านเลขที่ ชื่อ หรือเบอร์ลูกค้า

### ตั้งค่า

1. **Messaging API channel ต้องอยู่ใต้ provider เดียวกับ LINE Login channel ที่ใช้อยู่**
   - LINE userId แยกตาม provider ถ้าอยู่คนละ provider userId ที่ได้จากการล็อกอินจะส่งข้อความไม่ถึง
   - ถ้า OA เดิม (ที่ใช้แจ้งเตือนแอดมิน) อยู่คนละ provider ต้องสร้าง OA ใหม่ใต้ provider ของ LINE Login
2. ที่ LINE Developers > LINE Login channel > Basic settings > **Linked LINE Official Account** เลือก OA นี้
   - ตอนล็อกอิน LINE จะถามช่างให้เพิ่มเพื่อน OA (ระบบส่ง `bot_prompt=aggressive` ให้แอปช่างเมื่อเปิด `PROVIDER_LINE_ALERTS`)
   - แอปลูกค้าไม่เปลี่ยน
3. ที่ Messaging API channel > Messaging API > **Channel access token (long-lived)** กด Issue
4. ที่ LINE Official Account Manager คัดลอกลิงก์เพิ่มเพื่อน (`https://lin.ee/...`)
5. ตั้ง env ของ backend แล้วรีสตาร์ต API:
   ```
   PROVIDER_LINE_ALERTS=true
   LINE_MESSAGING_TOKEN=<channel access token>   # ว่าง = ใช้ LINE_CHANNEL_ACCESS_TOKEN
   LINE_OA_ADD_FRIEND_URL=https://lin.ee/xxxx      # การ์ด "เพิ่มเพื่อน LINE FixGo" ในหน้าหลักช่าง
   DISPATCH_OFFER_TIMEOUT_MS=180000                # ให้เวลาช่างเปิดเว็บมากดรับ (ค่าเริ่มต้น 90000)
   ```
   `FIXER_DOMAIN` (หรือ `PUBLIC_FIXER_URL`) ต้องตั้งไว้แล้ว ไม่อย่างนั้นข้อความจะไม่มีปุ่ม

### ทดสอบ

1. ล็อกอินเว็บแอปช่างด้วย LINE แล้วกดเพิ่มเพื่อนตอน LINE ถาม (หรือกดการ์ดในหน้าหลัก)
2. เปิด "พร้อมรับงาน" แล้วปิดหน้าเว็บ
3. สร้างงานจากเว็บลูกค้าในพื้นที่ของช่าง ช่างต้องได้ LINE ภายในไม่กี่วินาที กดปุ่มแล้วเปิดหน้าหลักที่มีงานรอรับ
4. ถ้าไม่ได้ LINE ดู log ของ API: `LINE ถึงช่าง ... ไม่สำเร็จ HTTP 4xx` (เช่น token ผิด หรือช่างยังไม่เป็นเพื่อน/บล็อก OA)

