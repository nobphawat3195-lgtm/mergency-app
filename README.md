# FixGo — On-demand roadside car repair platform

**FixGo** connects drivers whose car breaks down with nearby mechanics in Thailand, like a ride-hailing app for car repair.
A customer requests help. The system offers the job to the closest available mechanics. The mechanic quotes a price, which the customer approves before any work starts. The customer then pays by cash or by Thai QR PromptPay.

The platform has three parts: a customer app, a mechanic app ("FixGo Fixer") and an admin console. All of it is built from one codebase and deployable with a single command.

[ภาษาไทยด้านล่าง](#ภาษาไทย)

| Home | Booking | Live tracking | PromptPay + slip | Used-car report | Mechanic app |
|:-:|:-:|:-:|:-:|:-:|:-:|
| <img src="docs/screenshots/customer-home.png" width="150"> | <img src="docs/screenshots/customer-booking.png" width="150"> | <img src="docs/screenshots/customer-tracking.png" width="150"> | <img src="docs/screenshots/customer-promptpay.png" width="150"> | <img src="docs/screenshots/customer-inspection-report.png" width="150"> | <img src="docs/screenshots/provider-home.png" width="150"> |

*Screenshots are from the interactive web demo, which uses sample data. That is why they carry a "ตัวอย่าง" (demo) ribbon.*

## Highlights

- **Dispatch engine.** It offers each job to the nearest online mechanics in batches of 4, with a 90-second accept window per batch, a 25 km radius and up to 12 candidates. The first mechanic to accept wins, and this is safe under concurrent accepts. If nobody accepts, an admin gets a LINE alert and can re-dispatch or cancel the job.
- **Price approval before work.** The mechanic proposes a quote, and the customer approves or rejects it. Every state transition is validated on the server.
- **Payments that can't be faked.**
  - Thai QR PromptPay payloads (EMVCo + CRC-16) go straight to the owner's account.
  - A customer can upload a slip, but an order becomes `PAID` only when an admin confirms the money arrived or a signed Stripe webhook confirms it. Displaying a QR or pressing a button never marks an order paid.
  - The wallet is an idempotent ledger. For cash jobs the mechanic keeps the cash and is charged the platform fee instead of being credited twice.
- **Symptom-first booking.** Drivers tap what is wrong ("battery dead", "flat tyre", "locked out") instead of picking a service category. The app maps the symptom to the right service and skips straight to the vehicle type. A test checks every symptom against the seeded catalog.
- **Live map with ETA.** While the mechanic is on the way, the customer sees both pins on an OpenStreetMap map and an estimated arrival time. The server only shares the mechanic's position during that window and hides stale positions.
- **Mechanic trust card.** Photo, verified badge, rating, completed jobs, experience, and the vehicle and licence plate to look for.
- **Share with family + SOS.** A read-only tracking link (random 256-bit token, no login) that shows the status and the mechanic on the way but no phone numbers or prices. It expires 2 hours after the job ends and can be revoked. One-tap Thai emergency numbers are also available.
- **LINE Login (web, customers and mechanics).** OAuth 2.1 + OpenID Connect with a signed state cookie, nonce and a single-use 60-second ticket, so no access token ever appears in a URL. One channel serves both apps. New mechanics apply with a self-declared phone that the admin confirms before approval. It saves SMS OTP cost.
- **Owner and staff roles with an audit log.** Staff handle daily operations. Only the owner can confirm money in or out, see revenue, or manage the team. Roles are checked against the database on every request, so disabling an account takes effect immediately. Every login, approval and money action is recorded.
- **Owner finance report.** Revenue split by PromptPay (paid into the owner's account) and cash (held by the mechanic), commission earned, money held for mechanics, commission owed by mechanics, and a per-mechanic table, for any Thai-time date range, with CSV export.
- **Cash commission cap.** Cash jobs put the platform fee on the mechanic's wallet as a negative balance. Past a configurable limit (default 1,000 baht) the mechanic is switched offline and can't accept jobs until they pay back through a locked-amount PromptPay QR and the admin confirms the slip. Confirmation is idempotent.
- **Real-time tracking** uses Server-Sent Events, falls back to polling, and sends push notifications through FCM HTTP v1 with a self-signed JWT.
- **Used-car inspection mode.** A 134-point checklist in 11 categories, with measured values (paint thickness, tread, brake pads, battery), required photo evidence, weighted A–E grading and red flags for flood, crash, odometer and paperwork problems.
- **Security and privacy (PDPA).**
  - OTP login is rate-limited.
  - Mechanics are reviewed before they can take jobs: profile photo, licence plate, tool photos, services and vehicle types; admins approve or reject with a reason the mechanic sees in the app, and a rejected mechanic can fix and resubmit.
  - Order ownership and role guards return 404 to strangers.
  - Upload URLs must be signed and are write-once. Files are checked by magic bytes and served with `nosniff` and a CSP.
  - Internal fields such as the commission rate are stripped from API responses.
  - Account deletion removes personal data and files.
  - Admin alerts contain no customer PII.
- **Production-ready ops.**
  - Docker (API, Postgres and Caddy with auto-HTTPS).
  - `deploy/install.sh` does a one-command install on a fresh Ubuntu VPS.
  - Nightly backups.
  - The API refuses to start with missing or placeholder secrets.
  - A trial mode lets the team test before SMS is paid for.
- **CI (GitHub Actions)** runs:
  - backend typecheck and tests (112 unit tests)
  - Flutter analyze and tests (shared package and customer app)
  - a Docker boot test
  - a web image smoke test through the real Caddyfile
  - Android APK/AAB builds and an iOS build

## Architecture

```mermaid
flowchart LR
  C[Customer app<br/>Flutter · iOS / Android / Web] -->|HTTPS + SSE| API
  P[Mechanic app<br/>Flutter · iOS / Android / Web] -->|HTTPS| API
  A[Admin console<br/>HTML/JS] -->|HTTPS| API
  subgraph Server [VPS · Docker Compose]
    Caddy[Caddy<br/>auto-HTTPS + static web] --> API[NestJS API]
    API --> DB[(PostgreSQL<br/>Prisma)]
    API --> FS[(Uploads<br/>disk or S3/R2)]
  end
  API --> FCM[FCM push]
  API --> SMS[SMS OTP<br/>ThaiBulkSMS / Twilio]
  API --> LINE[LINE admin alerts]
  API -.optional.-> Stripe[Stripe PromptPay]
```

| Layer | Tech |
|---|---|
| Mobile & web apps | Flutter 3 (Dart), shared `fixgo_core` package: theme, models, API client, location |
| Backend | NestJS 11, TypeScript, Prisma 5, PostgreSQL 16, RxJS (SSE) |
| Infrastructure | Docker, Caddy, GitHub Actions |
| Integrations | FCM, ThaiBulkSMS/Twilio, Stripe (optional), LINE Messaging API, OpenStreetMap Nominatim |

```text
backend/                NestJS + Prisma API
apps/customer/          Flutter customer app (mobile + web)
apps/provider/          Flutter mechanic app (mobile + web)
admin/                  Admin console
packages/fixgo_core/    Shared Flutter code
deploy/                 Docker Compose, Caddyfile, install & backup scripts
docs/                   Product spec, deploy, payments, push, build guides
```

## Run locally

```bash
# database
docker run --name fixgo-db -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:16

# API
cd backend
cp .env.example .env
npm ci && npm run prisma:generate
npx prisma migrate deploy && npm run prisma:seed
npx ts-node prisma/create-admin.ts 0812345678 "Admin" '<a long password>'
npm run start:dev        # http://localhost:3000/api/health

# apps (web)
cd apps/customer         # or apps/provider
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

In development, OTP codes are returned by the API, so no SMS account is needed.
Quality checks: `npm run typecheck && npm test` (backend), `flutter analyze && flutter test` (Flutter).

**Deploy to a VPS:** `sudo bash deploy/install.sh`. See [docs/DEPLOY.md](docs/DEPLOY.md).

---

## ภาษาไทย

**FixGo** แพลตฟอร์มเรียกช่างซ่อมรถฉุกเฉินนอกสถานที่ 24 ชม. ประกอบด้วย 3 ส่วน:
- **แอปลูกค้า:** เรียกช่าง ติดตามงานแบบเรียลไทม์ ยืนยันราคาก่อนซ่อม จ่ายเงินสดหรือพร้อมเพย์ และจองตรวจรถมือสอง 134 จุด
- **แอปช่าง FixGo Fixer:** รับงานตามระยะทาง เสนอราคา อัปเดตสถานะ ดูกระเป๋ารายได้ และทำรายงานตรวจรถพร้อมรูปหลักฐาน
- **หน้าแอดมิน:** อนุมัติช่าง ตรวจสลิปพร้อมเพย์ จัดการงานที่ไม่มีช่างรับ และจัดการคำขอเบิกเงิน

**สิ่งที่ทำให้ใช้ง่ายกว่าแอปทั่วไป**
- เรียกช่างจาก "อาการรถ" ได้เลย ไม่ต้องรู้ว่าต้องเรียกช่างประเภทไหน
- แผนที่สดพร้อมเวลาช่างถึงโดยประมาณ
- การ์ดข้อมูลช่าง: รูป ป้ายยืนยันตัวตน คะแนน จำนวนงาน และทะเบียนรถ
- แชร์ลิงก์ให้ครอบครัวติดตาม และปุ่มโทรเบอร์ฉุกเฉิน
- เข้าสู่ระบบด้วย LINE บนเว็บ ทั้งลูกค้าและช่าง ไม่ต้องรอ OTP

**จุดเด่นทางเทคนิค**
- ระบบจับคู่ช่างแบบส่งเป็นกลุ่มตามระยะทาง
- สถานะงานอัปเดตทันทีด้วย SSE
- สร้าง QR พร้อมเพย์มาตรฐาน EMVCo เอง เงินเข้าบัญชีเจ้าของโดยตรง
- สถานะ "ชำระแล้ว" ต้องผ่านการยืนยันจริงเท่านั้น
- บัญชีรายได้แบบ ledger ป้องกันการเครดิตซ้ำ
- รองรับ PDPA: ลบบัญชีแล้วลบข้อมูลและไฟล์ให้ด้วย
- ติดตั้งขึ้นเซิร์ฟเวอร์ได้ด้วยคำสั่งเดียว
- CI ตรวจทุก push

**สถานะ:** โค้ดพร้อมใช้งานและผ่านการทดสอบทั้งหมด กำลังเตรียมเซิร์ฟเวอร์เพื่อเปิดให้บริการจริง

เอกสารเพิ่มเติม:
- [การติดตั้ง](docs/DEPLOY.md)
- [ระบบชำระเงิน](docs/PAYMENTS.md)
- [การแจ้งเตือน](docs/PUSH.md)
- [การ build แอป](docs/BUILD.md)
- [สเปกผลิตภัณฑ์](docs/01-overview-and-personas.md)

## Attribution

- The main 3D service icons were made by the project owner.
- Lightning, siren, mechanic and the 3D vehicle-type icons come from [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji) (MIT). The license is in `packages/fixgo_core/assets/icons/licenses/`.
- Noto Sans Thai is used under the SIL Open Font License (`packages/fixgo_core/assets/fonts/OFL.txt`).
