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

**ดูชื่อ artifact ก่อนแจก:** ถ้าตั้งค่าไม่ครบ CI ยัง build ให้ แต่เติมท้ายชื่อเพื่อเตือน
- `-no-api-url` ไม่ได้ตั้ง `API_BASE_URL` แอปจะต่อ `http://10.0.2.2:3000` (emulator) ใช้บนมือถือจริงไม่ได้
- `-debug-signed` ไม่มี keystore อัปโหลด Google Play ไม่ได้

ถ้า `API_BASE_URL` ไม่ขึ้นต้นด้วย `https://` CI จะหยุด build เพราะ Android release ไม่อนุญาต http ถ้าไม่ได้ตั้งค่า Firebase จะขึ้นคำเตือนว่า build นี้ไม่มีแจ้งเตือน push
ชื่อ `fixgo-customer-android` ที่ไม่มีคำต่อท้ายเท่านั้นที่พร้อมแจกหรืออัปโหลด

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

1. Apple Developer > Identifiers: สร้าง App ID ของทั้งสองแอป เปิด **Push Notifications** และ **Sign in with Apple**
   (แอปช่างเปิด **Time Sensitive Notifications** เพิ่ม) capability ต้องตรงกับ `ios/Runner/Runner.entitlements` ไม่งั้นเซ็นไม่ผ่าน
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

### ส่ง TestFlight ด้วย Codemagic (ง่ายที่สุด ไม่ต้องใช้ Mac ไม่ต้องทำใบรับรองเอง)

`codemagic.yaml` ที่ root ของ repo มี workflow `ios-customer` และ `ios-provider` Codemagic สร้างใบรับรองและ profile ให้เองจาก API key
แพ็กเกจฟรีมีนาที build macOS ให้ทุกเดือน พอสำหรับส่ง TestFlight เป็นครั้งคราว

1. App Store Connect > Users and Access > Integrations > App Store Connect API > + (สิทธิ์ **App Manager**) ดาวน์โหลด `.p8` จด Key ID และ Issuer ID
2. codemagic.io สมัครด้วย GitHub แล้ว Add application > เลือก repo นี้ > ประเภท Flutter App (codemagic.yaml)
3. Team settings > Integrations > **Developer Portal** > Connect: ตั้งชื่อ key ว่า `FixGo ASC` ใส่ Issuer ID, Key ID และไฟล์ `.p8`
4. Codemagic UI > Code signing identities > iOS certificates > **Generate certificate** (ใช้ key จากข้อ 3) แล้วที่ iOS provisioning profiles กด **Fetch profiles** หรือปล่อยให้ build สร้างให้
5. แอป > Environment variables: สร้างกลุ่ม `fixgo_build` ใส่ `API_BASE_URL`, `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_API_KEY`,
   `FIREBASE_CUSTOMER_IOS_APP_ID`, `FIREBASE_PROVIDER_IOS_APP_ID`, `SENTRY_CUSTOMER_DSN`, `SENTRY_PROVIDER_DSN` (ติ๊ก Secure ให้ค่าที่เป็นความลับ)
6. Start new build > เลือก workflow `ios-customer` หรือ `ios-provider` > Start build ราว 15-25 นาทีแอปจะขึ้นใน TestFlight

เลข build ใช้ `$BUILD_NUMBER` ของ Codemagic (เพิ่มเองทุกครั้งที่ build workflow นั้น) ถ้าเคยอัปโหลดเลขสูงกว่าด้วยวิธีอื่น ให้ตั้ง Build number ที่หน้า Codemagic ให้มากกว่าเดิม

### ส่ง TestFlight จาก GitHub Actions (ไม่ต้องใช้ Mac)

Workflow `iOS TestFlight` (`.github/workflows/ios-testflight.yml`) กดรันเองที่ Actions > iOS TestFlight > Run workflow เลือกแอปและใส่เลข build
Firebase ฝั่ง iOS ตั้งผ่าน `--dart-define` ไม่ต้องใช้ไฟล์ `GoogleService-Info.plist` แต่ต้องอัปโหลด **APNs Auth Key (.p8)** ที่ Firebase > Project settings > Cloud Messaging ไม่งั้น push ไม่ทำงานบน iPhone

| ชนิด | ชื่อ | ค่า |
|---|---|---|
| Variable | `IOS_TEAM_ID` | Team ID 10 ตัวอักษรจาก Apple Developer > Membership |
| Variable | `FIREBASE_CUSTOMER_IOS_APP_ID`, `FIREBASE_PROVIDER_IOS_APP_ID` | App ID ของแอป iOS แต่ละตัวใน Firebase (`1:...:ios:...`) |
| Secret | `IOS_DISTRIBUTION_CERT_BASE64`, `IOS_DISTRIBUTION_CERT_PASSWORD` | ใบรับรอง Apple Distribution (.p12) แปลงด้วย `base64 -i cert.p12` |
| Secret | `IOS_CUSTOMER_PROFILE_BASE64`, `IOS_PROVIDER_PROFILE_BASE64` | Provisioning profile แบบ App Store ของแต่ละ Bundle ID (`base64 -i x.mobileprovision`) |
| Secret | `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_BASE64` | App Store Connect API key (Users and Access > Integrations) และไฟล์ `.p8` แบบ base64 |

#### สร้างใบรับรองและ profile โดยไม่ต้องใช้ Mac

ใช้ `openssl` บน Linux หรือ Windows (Git Bash มีให้) ทำครั้งเดียว ใบรับรองใช้ร่วมกันทั้งสองแอป อายุ 1 ปี
**ห้าม commit ไฟล์ `.key` `.p12` `.p8` เข้า repo** เก็บไว้ใน password manager

1. สร้าง private key และ CSR
   ```bash
   openssl genrsa -out fixgo_distribution.key 2048
   openssl req -new -key fixgo_distribution.key -out fixgo_distribution.csr \
     -subj "/emailAddress=<อีเมล Apple ID>/CN=FixGo Distribution/C=TH"
   ```
2. Apple Developer > Certificates > + > **Apple Distribution** อัปโหลด `fixgo_distribution.csr` แล้วดาวน์โหลด `distribution.cer`
3. รวมเป็น `.p12` (ตั้งรหัสผ่านตอนถาม รหัสนี้คือ `IOS_DISTRIBUTION_CERT_PASSWORD`)
   ```bash
   openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
   openssl pkcs12 -export -legacy -inkey fixgo_distribution.key -in distribution.pem -out fixgo_distribution.p12
   ```
   `-legacy` ให้ keychain ของ macOS บน CI เปิดไฟล์ได้ (ถ้า openssl เป็นรุ่น 1.1 ให้ตัด `-legacy` ออก)
4. Apple Developer > Profiles > + > **App Store Connect** เลือก App ID เลือกใบรับรองจากข้อ 2 ทำสองครั้ง (`com.fixgo.fixgoCustomer`, `com.fixgo.fixgoProvider`) ดาวน์โหลด `.mobileprovision`
   ถ้าเปิด capability ใน App ID ทีหลัง (เช่น Time Sensitive) ต้องสร้าง profile ใหม่
5. App Store Connect > Users and Access > Integrations > App Store Connect API > + (สิทธิ์ App Manager) จด Key ID, Issuer ID และดาวน์โหลด `AuthKey_XXXX.p8` (ดาวน์โหลดได้ครั้งเดียว)
6. แปลงเป็น base64 บรรทัดเดียวแล้ววางใน GitHub Secrets
   ```bash
   base64 -w0 fixgo_distribution.p12          # IOS_DISTRIBUTION_CERT_BASE64
   base64 -w0 FixGo_Customer.mobileprovision  # IOS_CUSTOMER_PROFILE_BASE64
   base64 -w0 FixGo_Provider.mobileprovision  # IOS_PROVIDER_PROFILE_BASE64
   base64 -w0 AuthKey_XXXX.p8                 # APP_STORE_CONNECT_KEY_BASE64
   ```
   Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("fixgo_distribution.p12")) | Set-Clipboard`

ตัวแปร `API_BASE_URL`, `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_API_KEY`, `SENTRY_*_DSN` ใช้ชุดเดียวกับ Android
Profile ของแอปช่างต้องเปิด Push Notifications และ Time Sensitive Notifications ใน App ID

เลข build ต้องเพิ่มขึ้นทุกครั้งที่อัปโหลด ใช้ `--build-number=<เลข>` หรือแก้ `version:` ใน `pubspec.yaml`

## ก่อนส่งรีวิว

ดู checklist ใน `docs/APP_REVIEW.md`:
- บัญชีทดสอบของทีมรีวิว
- ลิงก์ privacy และ support
- ตาราง App Privacy
- วิธีลบบัญชี
