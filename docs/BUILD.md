# Build แอปสำหรับ store

GitHub Actions build แอปให้อัตโนมัติ:
- **Android build** (`.github/workflows/android.yml`): APK และ AAB ของทั้งสองแอปทุก PR ดาวน์โหลดได้ที่หน้า Actions > run > Artifacts (เก็บไว้ 14 วัน)
- **iOS build** (`.github/workflows/ios.yml`): คอมไพล์แบบยังไม่เซ็น เพื่อตรวจว่า build ผ่าน รันเฉพาะเมื่อไฟล์ iOS หรือ `pubspec.yaml` เปลี่ยน เพราะ runner macOS คิดนาทีแพงกว่า Linux 10 เท่า

## ค่าที่ตั้งใน GitHub

ตั้งที่ Settings > Secrets and variables > Actions

**Variables** (ไม่ใช่ความลับ เพราะค่าเหล่านี้จะอยู่ในแอปที่ติดตั้งอยู่แล้ว)

| ชื่อ | ค่า |
|---|---|
| `API_BASE_URL` | `https://api.<โดเมน>` |
| `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_API_KEY` | จาก Firebase > Project settings |
| `FIREBASE_CUSTOMER_ANDROID_APP_ID`, `FIREBASE_PROVIDER_ANDROID_APP_ID` | App ID ของแอป Android แต่ละตัว |
| `SENTRY_CUSTOMER_DSN`, `SENTRY_PROVIDER_DSN` | DSN ของโปรเจกต์ Sentry แยกแอป (ไม่ตั้งค่า = ไม่ส่ง crash report) |

**Secrets** (สำหรับเซ็นแอป Android ถ้าไม่ตั้ง CI จะเซ็นด้วย debug key ซึ่งใช้ติดตั้งทดสอบได้ แต่อัปโหลด Google Play ไม่ได้)

| ชื่อ | ค่า |
|---|---|
| `ANDROID_CUSTOMER_KEYSTORE_BASE64` | `base64 -w0 fixgo-customer-upload.jks` |
| `ANDROID_CUSTOMER_KEYSTORE_PASSWORD`, `ANDROID_CUSTOMER_KEY_ALIAS`, `ANDROID_CUSTOMER_KEY_PASSWORD` | ค่าที่ใช้ตอนสร้าง keystore |
| `ANDROID_PROVIDER_*` | ชุดเดียวกันของแอปช่าง |

## Android: สร้าง upload key (ครั้งเดียวต่อแอป)

```bash
keytool -genkey -v -keystore fixgo-customer-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

- **เก็บไฟล์ `.jks` และรหัสผ่านไว้ในที่ปลอดภัยนอก repo** (password manager) ถ้าหาย ต้องขอ Google รีเซ็ต upload key ซึ่งใช้เวลาหลายวัน
- ตอนสร้างแอปใน Play Console ให้เปิด **Play App Signing** (ค่าเริ่มต้น) Google จะเก็บ app signing key ให้ ส่วนเราเก็บแค่ upload key
- ถ้าจะ build บนเครื่องตัวเอง ให้สร้างไฟล์ `apps/<app>/android/key.properties` (ไฟล์นี้ถูก gitignore ไว้แล้ว)
  ```
  storeFile=/path/to/fixgo-customer-upload.jks
  storePassword=...
  keyAlias=upload
  keyPassword=...
  ```

อัปโหลดครั้งแรก: Play Console > Testing > Internal testing > Create release แล้วอัปโหลด `app-release.aab` จาก Artifacts

## iOS: เซ็นและส่ง TestFlight

ต้องมีบัญชี Apple Developer และ Mac ที่ติดตั้ง Xcode (หรือใช้บริการ CI ที่มี macOS เช่น Codemagic)

1. Apple Developer > Identifiers: สร้าง App ID ของทั้งสองแอป และเปิด **Push Notifications**
2. App Store Connect > My Apps: สร้างแอปทั้งสองตัวด้วย bundle id เดียวกับข้อ 1
3. บน Mac:
   ```bash
   cd apps/customer
   flutter build ipa --release \
     --dart-define=API_BASE_URL=https://api.<โดเมน> \
     --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_SENDER_ID=... \
     --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_IOS_APP_ID=... \
     --dart-define=SENTRY_DSN=https://...@o0.ingest.sentry.io/0
   ```
   ครั้งแรกให้เปิด `ios/Runner.xcworkspace` ใน Xcode แล้วเลือก Team ที่ Signing & Capabilities (Automatic signing)
4. อัปโหลด `build/ios/ipa/*.ipa` ผ่านแอป **Transporter** หรือ `xcrun altool` แล้วเพิ่มผู้ทดสอบใน TestFlight

เลข build ต้องเพิ่มขึ้นทุกครั้งที่อัปโหลด ใช้ `--build-number=<เลข>` หรือแก้ `version:` ใน `pubspec.yaml`

## ก่อนส่งรีวิว

ดู checklist ใน `docs/APP_REVIEW.md`:
- บัญชีทดสอบของทีมรีวิว
- ลิงก์ privacy และ support
- ตาราง App Privacy
- วิธีลบบัญชี
