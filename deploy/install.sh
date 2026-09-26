#!/usr/bin/env bash
# ติดตั้ง FixGo บนเซิร์ฟเวอร์ Ubuntu ใหม่ (เช่น Oracle Cloud Always Free) ด้วยคำสั่งเดียว
#
#   git clone <repo> fixgo && cd fixgo && sudo bash deploy/install.sh
#
# สคริปต์จะ:
#   1. ติดตั้ง Docker และเปิดพอร์ต 80/443 ในเครื่อง
#   2. ถามค่าที่จำเป็นแล้วสร้าง deploy/.env.production (ค่าลับสุ่มให้เอง) ถ้ายังไม่มี
#   3. build และเปิดระบบ ใส่หมวดบริการ/ราคา และสร้างบัญชีแอดมิน
# รันซ้ำได้: ถ้ามี .env.production แล้วจะไม่ถามใหม่ แค่อัปเดตระบบ
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
ENV_FILE="$ROOT/deploy/.env.production"
COMPOSE=(docker compose -f "$ROOT/deploy/docker-compose.yml" --env-file "$ENV_FILE")

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m%s\033[0m\n' "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "ต้องรันด้วย sudo: sudo bash deploy/install.sh"

# ---------- 1. Docker ----------
if ! command -v docker >/dev/null 2>&1; then
  say "ติดตั้ง Docker"
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || fail "ไม่พบ docker compose plugin"

# ---------- 2. Firewall ในเครื่อง ----------
# image ของ Oracle Cloud มี iptables REJECT ทุกพอร์ตยกเว้น SSH
if command -v iptables >/dev/null 2>&1; then
  for port in 80 443; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null ||
      iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
  done
  iptables -C INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null ||
    iptables -I INPUT 1 -p udp --dport 443 -j ACCEPT
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true
fi
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null
  ufw allow 443 >/dev/null
fi

# ---------- 3. Swap (เครื่อง RAM น้อย build เว็บแล้วอาจหน่วยความจำไม่พอ) ----------
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$mem_mb" -lt 3500 ] && ! swapon --show | grep -q .; then
  say "เพิ่ม swap 2GB (RAM ${mem_mb}MB)"
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---------- 4. ค่าตั้งระบบ ----------
ask() { # ask <ตัวแปร> <คำถาม> [ค่าเริ่มต้น]
  local answer
  read -r -p "$2${3:+ [$3]}: " answer
  printf -v "$1" '%s' "${answer:-${3:-}}"
}
ask_secret() {
  local answer
  read -r -s -p "$2: " answer
  echo
  printf -v "$1" '%s' "$answer"
}
rand() { openssl rand -hex 32; }

if [ ! -f "$ENV_FILE" ]; then
  say "ตั้งค่าระบบ (กด Enter เพื่อใช้ค่าในวงเล็บ)"
  ask DOMAIN "โดเมนหลัก เช่น fixgo.duckdns.org หรือ fixgo.co.th"
  [ -n "$DOMAIN" ] || fail "ต้องใส่โดเมน"
  echo "จะใช้: https://$DOMAIN (ลูกค้า) https://fixer.$DOMAIN (ช่าง) https://admin.$DOMAIN (แอดมิน) https://api.$DOMAIN (API)"

  ask PROMPTPAY_ID "เบอร์พร้อมเพย์ที่รับเงิน (10 หลัก)"
  ask PROMPTPAY_NAME "ชื่อบัญชีพร้อมเพย์ ให้ตรงกับที่แอปธนาคารแสดง"
  ask COMPANY "ชื่อกิจการ (แสดงในนโยบายความเป็นส่วนตัว)" "FixGo"
  ask CONTACT_PHONE "เบอร์ติดต่อทีมงาน (แสดงปุ่มโทรบนหน้าเว็บ)" "$PROMPTPAY_ID"
  ask CONTACT_EMAIL "อีเมลติดต่อ"
  ask ADDRESS "ที่อยู่กิจการ (เว้นว่างได้)"

  echo
  echo "SMS สำหรับรหัส OTP:"
  echo "  1) ThaiBulkSMS (ต้องมีบัญชีและชื่อผู้ส่งที่อนุมัติแล้ว)"
  echo "  2) ยังไม่ใช้ SMS: โหมดทดลอง เข้าสู่ระบบได้เฉพาะเบอร์ทีมงานด้วยรหัสตายตัว"
  ask SMS_CHOICE "เลือก" "2"
  SMS_BLOCK=""
  REVIEW_PHONES=""
  REVIEW_CODE=""
  if [ "$SMS_CHOICE" = "1" ]; then
    ask TBS_KEY "ThaiBulkSMS API key"
    ask_secret TBS_SECRET "ThaiBulkSMS API secret (พิมพ์แล้วจะไม่แสดง)"
    ask TBS_SENDER "ชื่อผู้ส่งที่อนุมัติแล้ว" "FixGo"
    SMS_BLOCK="SMS_PROVIDER=thaibulksms
THAIBULKSMS_API_KEY=$TBS_KEY
THAIBULKSMS_API_SECRET=$TBS_SECRET
THAIBULKSMS_SENDER=$TBS_SENDER
THAIBULKSMS_FORCE=corporate"
  else
    ask REVIEW_PHONES "เบอร์ทีมงานที่ให้ทดลองใช้ คั่นด้วยจุลภาค เช่น 0811111111,0822222222"
    [ -n "$REVIEW_PHONES" ] || fail "โหมดทดลองต้องมีเบอร์ทีมงานอย่างน้อย 1 เบอร์"
    REVIEW_CODE=$(printf '%06d' $(( $(od -An -N4 -tu4 /dev/urandom) % 1000000 )))
    SMS_BLOCK="SMS_PROVIDER=none"
  fi

  umask 077
  cat > "$ENV_FILE" <<EOF
# สร้างโดย deploy/install.sh $(date -u +%Y-%m-%d) ดูคำอธิบายทุกค่าใน deploy/.env.production.example
API_DOMAIN=api.$DOMAIN
ADMIN_DOMAIN=admin.$DOMAIN
WEB_DOMAIN=$DOMAIN
FIXER_DOMAIN=fixer.$DOMAIN
CORS_ORIGIN=https://$DOMAIN,https://fixer.$DOMAIN,https://admin.$DOMAIN
ADMIN_URL=https://admin.$DOMAIN

POSTGRES_PASSWORD=$(rand)
JWT_SECRET=$(rand)
JWT_EXPIRES_SECONDS=2592000
OTP_SECRET=$(rand)

STORAGE_PROVIDER=local

$SMS_BLOCK
REVIEW_LOGIN_PHONES=$REVIEW_PHONES
REVIEW_LOGIN_CODE=$REVIEW_CODE

PAYMENT_PROVIDER=promptpay_manual
PROMPTPAY_ID=$PROMPTPAY_ID
PROMPTPAY_NAME="$PROMPTPAY_NAME"

PUSH_PROVIDER=console
ADMIN_ALERT_CHANNEL=none

LEGAL_COMPANY_NAME="$COMPANY"
LEGAL_CONTACT_EMAIL=$CONTACT_EMAIL
LEGAL_CONTACT_PHONE=$CONTACT_PHONE
LEGAL_ADDRESS="$ADDRESS"
LEGAL_UPDATED_AT=$(date +%Y-%m-%d)
EOF
  chmod 600 "$ENV_FILE"
  say "บันทึกค่าไว้ที่ deploy/.env.production แล้ว (อ่านได้เฉพาะ root)"
else
  say "ใช้ค่าเดิมใน deploy/.env.production"
fi

# ---------- 5. เปิดระบบ ----------
say "build และเปิดระบบ (ครั้งแรกประมาณ 5-15 นาที)"
"${COMPOSE[@]}" up -d --build

say "รอ API พร้อม"
for _ in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T api node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 5
done
[ "${ready:-}" = 1 ] || fail "API ไม่พร้อม ดู log: docker compose -f deploy/docker-compose.yml --env-file deploy/.env.production logs api"

say "ใส่หมวดบริการและราคา (รันซ้ำได้ ไม่ลบของเดิม)"
"${COMPOSE[@]}" exec -T api node dist-scripts/prisma/seed.js

if [ ! -f "$ROOT/deploy/.admin-created" ]; then
  say "สร้างบัญชีแอดมิน"
  ask ADMIN_PHONE "เบอร์แอดมิน (ใช้ล็อกอินหน้าแอดมิน)" "$(grep '^LEGAL_CONTACT_PHONE=' "$ENV_FILE" | cut -d= -f2)"
  ask ADMIN_NAME "ชื่อแอดมิน" "แอดมิน"
  ask_secret ADMIN_PASSWORD "รหัสผ่านแอดมิน (อย่างน้อย 12 ตัว พิมพ์แล้วจะไม่แสดง)"
  [ "${#ADMIN_PASSWORD}" -ge 12 ] || fail "รหัสผ่านสั้นเกินไป รัน sudo bash deploy/install.sh ใหม่ได้"
  "${COMPOSE[@]}" exec -T api node dist-scripts/prisma/create-admin.js "$ADMIN_PHONE" "$ADMIN_NAME" "$ADMIN_PASSWORD"
  touch "$ROOT/deploy/.admin-created"
fi

# ---------- 6. สำรองข้อมูลทุกวัน ----------
CRON_LINE="0 3 * * * $ROOT/deploy/backup.sh >> /var/log/fixgo-backup.log 2>&1"
{ crontab -l 2>/dev/null | grep -v 'deploy/backup.sh' || true; echo "$CRON_LINE"; } | crontab -

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
say "เสร็จแล้ว"
cat <<EOF
  เว็บลูกค้า   https://$WEB_DOMAIN
  เว็บช่าง     https://$FIXER_DOMAIN
  หน้าแอดมิน  https://$ADMIN_DOMAIN
  ตรวจระบบ    https://$API_DOMAIN/api/health

  HTTPS อาจใช้เวลา 1-2 นาทีหลังเปิดครั้งแรก (Caddy ขอใบรับรองให้อัตโนมัติ)
  สำรองข้อมูลทุกวันตี 3 ไว้ที่ deploy/backups/ ควรคัดลอกออกนอกเครื่องเป็นระยะ
EOF
if [ "${SMS_PROVIDER:-}" = "none" ]; then
  cat <<EOF

  โหมดทดลอง (ยังไม่ส่ง SMS): เข้าสู่ระบบได้เฉพาะเบอร์ $REVIEW_LOGIN_PHONES
  รหัส OTP ของทุกเบอร์นี้คือ $REVIEW_LOGIN_CODE (ดูอีกครั้งได้ใน deploy/.env.production)
  เมื่อพร้อมเปิดให้ทุกคน: ใส่ค่า ThaiBulkSMS ใน deploy/.env.production เปลี่ยน SMS_PROVIDER=thaibulksms
  ลบ REVIEW_LOGIN_PHONES แล้วรัน sudo bash deploy/install.sh อีกครั้ง
EOF
fi
