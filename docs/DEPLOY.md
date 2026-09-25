# Deploy production

ใช้ VPS เครื่องเดียวรัน 3 container:
- **api**: NestJS จาก `backend/Dockerfile` รัน migration ให้เองทุกครั้งที่เริ่ม
- **db**: PostgreSQL 16 ข้อมูลอยู่ใน volume `pgdata`
- **caddy**: HTTPS อัตโนมัติ build จาก `deploy/web.Dockerfile` เสิร์ฟ 4 โดเมน

| โดเมน (ตัวแปร) | เสิร์ฟอะไร |
|---|---|
| `WEB_DOMAIN` | เว็บแอปลูกค้า FixGo |
| `FIXER_DOMAIN` | เว็บแอปช่าง FixGo Fixer |
| `ADMIN_DOMAIN` | หน้าแอดมิน (ต้องขึ้นต้นด้วย `admin.` และอยู่คู่กับ `api.` ของโดเมนเดียวกัน) |
| `API_DOMAIN` | API |

เว็บแอปทั้งสองคือโค้ดเดียวกับแอปมือถือ build เป็นเว็บ ผู้ใช้กด "เพิ่มลงหน้าจอโฮม" ในเบราว์เซอร์แล้วจะเปิดใช้เหมือนแอปได้

**ข้อจำกัดของเว็บ:**
- ไม่มีแจ้งเตือน push
- ช่างต้องเปิดหน้าเว็บค้างไว้ระหว่างพร้อมรับงาน (ระบบเช็กงานใหม่ทุก 10 วินาที)
- ถ้าช่างใช้ Android ให้ติดตั้งไฟล์ APK จาก CI แทน (ไม่ต้องผ่าน Google Play) จะได้รับแจ้งเตือนงานเข้า

รูปทั้งหมดอัปโหลดจากแอปตรงไป object storage (Cloudflare R2 หรือ S3) ไม่ผ่านเซิร์ฟเวอร์ เครื่องจึงใช้สเปกไม่สูงได้

## 1. สิ่งที่ต้องมี

| รายการ | คำแนะนำ |
|---|---|
| VPS | 2 vCPU / 2–4 GB RAM / 40 GB, Ubuntu 24.04 เลือก region สิงคโปร์ ตัวเลือกฟรี: Oracle Cloud Always Free (ARM, VM.Standard.A1.Flex) ใช้กับชุดนี้ได้ |
| โดเมน | ชี้โดเมนหลัก และ `api.` `admin.` `fixer.` ไปที่ IP ของ VPS ตัวเลือกฟรี: DuckDNS จองชื่อเดียว เช่น `fixgo.duckdns.org` แล้ว `api.fixgo.duckdns.org` ฯลฯ จะชี้ไปที่ IP เดียวกันเอง |
| Object storage | Cloudflare R2 (ไม่มีค่า egress) หรือ AWS S3 |
| SMS | ThaiBulkSMS (ส่งในไทย ราคาถูก ต้องขออนุมัติชื่อผู้ส่งก่อน 1–3 วันทำการ) หรือ Twilio |
| ชำระเงิน | พร้อมเพย์ของเจ้าของ + แอดมินตรวจสลิป (เริ่มต้น) หรือ Stripe ดู `docs/PAYMENTS.md` |
| Push | Firebase ดู `docs/PUSH.md` |

## 2. เตรียมเครื่อง

```bash
# ติดตั้ง Docker
curl -fsSL https://get.docker.com | sh
# Oracle Cloud: เปิดพอร์ต 80/443 ที่ Networking > Virtual Cloud Network > Security List ด้วย
# (image ของ Oracle ปิดพอร์ตไว้ทั้งใน cloud และใน iptables ของเครื่อง)
# เปิดเฉพาะ SSH และเว็บ
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw allow 443/udp && ufw enable

git clone https://github.com/<owner>/mergency-app.git /opt/fixgo
cd /opt/fixgo
cp deploy/.env.production.example deploy/.env.production
nano deploy/.env.production   # กรอกทุกค่า ค่าลับสุ่มด้วย: openssl rand -hex 32
chmod 600 deploy/.env.production
```

ถ้าค่าไหนขาดหรือยังเป็นค่าตัวอย่าง API จะไม่ยอมเริ่มและบอกชื่อตัวแปรที่ขาด ตั้งใจให้ทำงานแบบนี้เพื่อกันการเปิดใช้ระบบที่ตั้งค่าไม่ครบ

## 3. Object storage (Cloudflare R2)

1. R2 > Create bucket ตั้งชื่อ `fixgo-uploads`
2. Bucket > Settings > Custom Domains ผูก `files.<โดเมน>` แล้วนำ URL นี้ไปใส่ใน `S3_PUBLIC_BASE_URL`
3. R2 > Manage API tokens สร้าง token แบบ Object Read & Write เฉพาะ bucket นี้ แล้วใส่ใน `S3_ACCESS_KEY_ID` และ `S3_SECRET_ACCESS_KEY`
4. ตั้ง `S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com` และ `S3_REGION=auto`

**ความเป็นส่วนตัว:**
- ไฟล์ตั้งชื่อด้วย UUID สุ่ม คนที่ไม่มีลิงก์เดาไม่ได้
- backend รับเฉพาะ URL ที่ผู้ใช้คนนั้นอัปโหลดผ่าน `/api/uploads/presign` เอง
- เมื่อผู้ใช้ลบบัญชี backend จะลบรูปงานและรูปเครื่องมือช่างออกจาก bucket ให้

## 4. เปิดระบบ

```bash
cd /opt/fixgo
docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production up -d --build

# ครั้งแรกเท่านั้น: ใส่หมวดบริการและราคา (รันซ้ำได้ ไม่ลบของเดิม)
docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production \
  exec api node dist-scripts/prisma/seed.js

# สร้างบัญชีแอดมิน
docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production \
  exec api node dist-scripts/prisma/create-admin.js 08xxxxxxxx "ชื่อแอดมิน" '<รหัสผ่านยาว>'
```

ตรวจว่าระบบทำงาน:
- `https://api.<โดเมน>/api/health` ต้องตอบ `{"status":"ok","database":"up"}`
- `https://api.<โดเมน>/api/legal/privacy` ต้องเปิดได้ และต้องไม่มีช่องสีเหลืองที่ยังไม่กรอก
- `https://admin.<โดเมน>` เปิดหน้าแอดมินได้ หน้านี้เรียก API ที่ `api.<โดเมน>` เอง
- `https://<โดเมน>` เปิดเว็บลูกค้า และ `https://fixer.<โดเมน>` เปิดเว็บช่าง ล็อกอินด้วย OTP ได้
  - ถ้าล็อกอินแล้วขึ้นว่าเชื่อมต่อไม่ได้ ให้ตรวจว่า `CORS_ORIGIN` มีทั้งสองโดเมนนี้

## 5. เชื่อมบริการภายนอก

- **Stripe** (เฉพาะเมื่อใช้ `PAYMENT_PROVIDER=stripe`):
  - ที่ Developers > Webhooks ให้เพิ่ม endpoint `https://api.<โดเมน>/api/payments/stripe/webhook` แล้วเลือก event `payment_intent.succeeded`
  - นำ signing secret (`whsec_…`) ไปใส่ใน `STRIPE_WEBHOOK_SECRET`
- **เว็บแอป:** ไม่ต้องตั้งเพิ่ม `docker compose ... up -d --build` จะ build เว็บด้วย `API_BASE_URL=https://$API_DOMAIN` ให้เอง ครั้งแรกใช้เวลาประมาณ 5–10 นาที
- **แอปมือถือ:** build แอปด้วย `--dart-define=API_BASE_URL=https://api.<โดเมน>` และค่า Firebase ตาม `docs/PUSH.md`
- **ทีมรีวิว App Store:**
  - ตั้ง `REVIEW_LOGIN_PHONES` และ `REVIEW_LOGIN_CODE`
  - รัน `exec -e REVIEW_PROVIDER_PHONE=08xxxxxxxx api node dist-scripts/prisma/seed-review.js`
  - ดูรายละเอียดใน `docs/APP_REVIEW.md`

หลังแก้ `.env.production` ต้องรัน `up -d` อีกครั้ง container จะถูกสร้างใหม่ด้วยค่าใหม่

### แจ้งเตือนทีมงานผ่าน LINE

ระบบจะส่งข้อความเข้ากลุ่ม LINE ของทีมงานเมื่อเกิด 3 เหตุการณ์:
- **ไม่มีช่างรับงาน**
- **ช่างสมัครใหม่**
- **คำขอเบิกเงิน**

ในข้อความจะมีแค่เลขงาน ประเภทบริการ และเขตกับจังหวัด ไม่มีเบอร์โทรหรือชื่อลูกค้า รายละเอียดเต็มให้ดูในหน้าแอดมินที่ต้องล็อกอิน

ขั้นตอนตั้งค่า:
1. สร้าง LINE Official Account แล้วเปิด Messaging API ที่ [LINE Developers](https://developers.line.biz)
2. ออก channel access token (long-lived) แล้วใส่ใน `LINE_CHANNEL_ACCESS_TOKEN`
3. เชิญบอตเข้ากลุ่ม LINE ของทีมงาน
4. หา groupId ของกลุ่มจาก webhook event แล้วใส่ใน `LINE_ADMIN_TO`
5. ตั้ง `ADMIN_ALERT_CHANNEL=line`

ถ้าใช้ Slack หรือ Discord ให้ตั้ง `ADMIN_ALERT_CHANNEL=webhook` และใส่ URL ของ webhook ใน `ADMIN_ALERT_WEBHOOK_URL`

เมื่อแอดมินได้รับแจ้งว่าไม่มีช่างรับงาน ให้เปิดหน้าแอดมิน ส่วน "งานที่ไม่มีช่างรับ" จะแสดงเบอร์ลูกค้าและปุ่มแผนที่ แล้วเลือกจัดการได้ 2 ทาง:
- **ส่งหาช่างอีกครั้ง** เช่น หลังโทรเรียกช่างให้เปิดแอปแล้ว
- **ยกเลิกงาน** ต้องใส่เหตุผล และเหตุผลนี้จะส่งถึงลูกค้าทาง push

### ติดตามงานแบบ real-time

หน้าติดตามงานในแอปลูกค้าเปิดการเชื่อมต่อ Server-Sent Events ที่ `GET /api/orders/:id/events` ไว้ตลอดที่หน้านั้นเปิดอยู่
- เมื่อช่างรับงาน, เดินทาง, เสนอราคา, ขยับตำแหน่ง หรือปิดงาน แอปจะดึงข้อมูลใหม่ภายในไม่ถึง 1 วินาที
- Caddy ส่งต่อ event-stream ได้เลยโดยไม่ต้องตั้งค่าเพิ่ม
- ถ้าการเชื่อมต่อหลุด แอปจะต่อใหม่เอง และระหว่างนั้นจะดึงข้อมูลเป็นรอบแทน

ข้อจำกัด: event ส่งกันภายใน process เดียว ถ้าจะรัน API หลาย instance ต้องเปลี่ยนไปใช้ Redis pub/sub ก่อน

## 6. อัปเดตเวอร์ชัน

```bash
cd /opt/fixgo && git pull
docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production up -d --build
```

migration ใหม่จะรันเองตอน API เริ่ม (`prisma migrate deploy` รันเฉพาะ migration ที่ยังไม่ได้รัน ไม่ลบข้อมูล) ควร backup ก่อนอัปเดตทุกครั้ง

## 7. Backup และกู้คืน

```bash
# สำรองทุกวันตี 3 (เวลาเครื่อง)
crontab -e
0 3 * * * /opt/fixgo/deploy/backup.sh >> /var/log/fixgo-backup.log 2>&1
```

- ไฟล์อยู่ที่ `deploy/backups/` เก็บย้อนหลัง 14 วัน
- **ต้องคัดลอกออกนอกเครื่องด้วย** เช่น ใช้ `rclone` ไปอีก bucket ถ้า VPS เสียจะได้ไม่เสีย backup ไปด้วย

กู้คืน (ข้อมูลปัจจุบันจะถูกแทนที่):

```bash
gunzip -c deploy/backups/fixgo-YYYYMMDD-HHMMSS.sql.gz | \
  docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production \
  exec -T db psql -U fixgo -d fixgo
```

ควรลองกู้คืนบนเครื่องทดสอบอย่างน้อยเดือนละครั้ง จะได้มั่นใจว่า backup ใช้งานได้จริง

## 8. ดู log และแก้ปัญหา

```bash
docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production ps
docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production logs -f api
```

| อาการ | สาเหตุที่พบบ่อย |
|---|---|
| api ไม่ยอมเริ่ม แล้ว log แจ้ง `... is required` | ยังไม่ได้ตั้งตัวแปรนั้นใน `.env.production` |
| HTTPS ไม่ขึ้น | DNS ยังไม่ชี้มาที่เครื่อง หรือพอร์ต 80/443 ถูก firewall ปิด |
| แอปอัปโหลดรูปไม่ได้ | ค่า `S3_*` ผิด หรือ token ของ R2 ไม่มีสิทธิ์เขียน |
| ชำระเงินแล้วสถานะไม่เปลี่ยน | URL webhook หรือ `STRIPE_WEBHOOK_SECRET` ไม่ตรงกับที่ตั้งไว้ใน Stripe ดูได้ที่ Stripe > Webhooks > Event deliveries |
