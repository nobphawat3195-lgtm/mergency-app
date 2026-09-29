#!/usr/bin/env bash
# ตรวจสุขภาพระบบหลังติดตั้ง รันเมื่อไหร่ก็ได้ ไม่แก้ไขอะไร
#
#   sudo bash deploy/doctor.sh           ตรวจผ่านอินเทอร์เน็ตแบบที่ลูกค้าเห็น
#   sudo bash deploy/doctor.sh --local   ต่อ Caddy ในเครื่องตรง ไม่พึ่ง DNS (แยกปัญหา DNS ออกจากปัญหาเซิร์ฟเวอร์)
#   --insecure ยอมรับใบรับรองที่ไม่ใช่ของจริง (ใช้กับเครื่องซ้อมเท่านั้น)
#
# exit 0 = ปกติ (อาจมีคำเตือน), 1 = มีข้อที่ต้องแก้
# ไม่แสดงค่าลับใดๆ จาก .env.production
set -uo pipefail

cd "$(dirname "$0")"
ENV_FILE=.env.production
COMPOSE=(docker compose -f docker-compose.yml --env-file "$ENV_FILE")

LOCAL=0
INSECURE=0
for arg in "$@"; do
  case "$arg" in
    --local) LOCAL=1 ;;
    --insecure) INSECURE=1 ;;
    *) echo "ไม่รู้จัก $arg (ใช้ได้: --local --insecure)" >&2; exit 2 ;;
  esac
done

errors=0
warnings=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; warnings=$((warnings + 1)); }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; errors=$((errors + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

[ -f "$ENV_FILE" ] || { echo "ไม่พบ deploy/$ENV_FILE ยังไม่ได้ติดตั้ง: sudo bash deploy/install.sh" >&2; exit 1; }
# อ่านเฉพาะค่าที่ต้องใช้ ไม่ source ทั้งไฟล์
env_get() { grep -m1 "^$1=" "$ENV_FILE" | cut -d= -f2- | sed 's/^"//; s/"$//'; }
WEB_DOMAIN=$(env_get WEB_DOMAIN)
FIXER_DOMAIN=$(env_get FIXER_DOMAIN)
ADMIN_DOMAIN=$(env_get ADMIN_DOMAIN)
API_DOMAIN=$(env_get API_DOMAIN)

curl_opts=(-sS --max-time 15)
[ "$INSECURE" = 1 ] && curl_opts+=(-k)
fetch() { # fetch <host> <path> → พิมพ์ body บรรทัดแรกๆ และ http code บรรทัดสุดท้าย
  local host=$1 path=$2 extra=()
  [ "$LOCAL" = 1 ] && extra=(--resolve "$host:443:127.0.0.1")
  curl "${curl_opts[@]}" "${extra[@]}" -w '\n%{http_code}' "https://$host$path" 2>&1
}

section "คอนเทนเนอร์"
for svc in db api caddy; do
  state=$("${COMPOSE[@]}" ps --format '{{.State}} {{.Health}}' "$svc" 2>/dev/null | head -1)
  case "$state" in
    "running healthy" | "running ") ok "$svc ทำงานอยู่" ;;
    running*) warn "$svc ทำงานอยู่แต่สถานะ: ${state#running }" ;;
    "") bad "$svc ไม่ได้ทำงาน: sudo bash deploy/install.sh หรือดู log ด้วย docker compose logs $svc" ;;
    *) bad "$svc สถานะ $state" ;;
  esac
done

section "เว็บและ HTTPS$([ "$LOCAL" = 1 ] && echo ' (ต่อในเครื่อง)')"
for pair in "$WEB_DOMAIN|/|เว็บลูกค้า" "$FIXER_DOMAIN|/|เว็บช่าง" "$ADMIN_DOMAIN|/|หน้าแอดมิน" "$API_DOMAIN|/api/health|API"; do
  IFS='|' read -r host path label <<<"$pair"
  out=$(fetch "$host" "$path")
  code=$(printf '%s' "$out" | tail -n1)
  if [ "$code" = 200 ]; then
    ok "$label https://$host"
  elif printf '%s' "$out" | grep -qi 'certificate\|SSL'; then
    bad "$label https://$host ใบรับรอง HTTPS ยังไม่พร้อม: รอ 1-2 นาทีหลังติดตั้ง ถ้ายังไม่ได้ ตรวจ DNS ด้วย bash deploy/preflight.sh ${WEB_DOMAIN}"
  else
    bad "$label https://$host ตอบ ${code:-ไม่ได้} $(printf '%s' "$out" | head -n1 | cut -c1-80)"
  fi
done

section "ระบบหลังบ้าน"
health=$(fetch "$API_DOMAIN" /api/health | head -n1)
if printf '%s' "$health" | grep -q '"database":"up"'; then
  ok "ฐานข้อมูลเชื่อมต่อได้"
else
  bad "API หรือฐานข้อมูลไม่ตอบ: docker compose logs db api"
fi
# API ล่มแล้วผล LINE จะดูเหมือนปิด ข้ามไปเพื่อไม่ให้เข้าใจผิด
for app in $(printf '%s' "$health" | grep -q '"database":"up"' && echo customer provider); do
  label=$([ "$app" = customer ] && echo ลูกค้า || echo ช่าง)
  line=$(fetch "$API_DOMAIN" "/api/auth/line/config?app=$app" | head -n1)
  if printf '%s' "$line" | grep -q '"enabled":true'; then
    ok "LINE Login เปิดสำหรับ$label"
  else
    warn "LINE Login ปิดอยู่สำหรับ$label (ใส่ LINE_LOGIN_CHANNEL_ID/SECRET ใน deploy/$ENV_FILE)"
  fi
done

promptpay=$(env_get PROMPTPAY_ID | tr -d ' -')
if [[ "$promptpay" =~ ^0[0-9]{9}$ || "$promptpay" =~ ^[0-9]{13}$ ]]; then
  ok "ตั้งเบอร์/เลขพร้อมเพย์แล้ว"
else
  bad "PROMPTPAY_ID ต้องเป็นเบอร์มือถือ 10 หลักหรือเลข 13 หลักที่ผูกพร้อมเพย์ (QR ร้านค้าใช้ไม่ได้)"
fi
if [ "$(env_get SMS_PROVIDER)" = none ]; then
  warn "ยังไม่ส่ง SMS: เข้าด้วยเบอร์โทรได้เฉพาะเบอร์ทีมงาน ลูกค้าและช่างใช้ LINE"
else
  ok "SMS: $(env_get SMS_PROVIDER)"
fi

section "ความปลอดภัยและการสำรองข้อมูล"
perm=$(stat -c %a "$ENV_FILE")
if [ "$perm" = 600 ]; then ok "deploy/$ENV_FILE อ่านได้เฉพาะ root"; else bad "deploy/$ENV_FILE สิทธิ์ $perm ต้องเป็น 600: chmod 600 deploy/$ENV_FILE"; fi

if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q 'deploy/backup.sh'; then
  ok "ตั้งสำรองข้อมูลอัตโนมัติทุกวันแล้ว"
else
  bad "ไม่พบ cron สำรองข้อมูล: รัน sudo bash deploy/install.sh อีกครั้ง"
fi
latest=$(ls -1t backups/fixgo-*.sql.gz 2>/dev/null | head -1)
if [ -z "$latest" ]; then
  warn "ยังไม่มีไฟล์สำรอง (สำรองครั้งแรกตี 3 หรือรันเองได้: sudo deploy/backup.sh)"
else
  age_h=$(( ($(date +%s) - $(stat -c %Y "$latest")) / 3600 ))
  if [ "$age_h" -le 26 ]; then
    ok "สำรองล่าสุด ${age_h} ชม.ก่อน ($(basename "$latest"))"
  else
    bad "สำรองล่าสุดเมื่อ ${age_h} ชม.ก่อน ดู /var/log/fixgo-backup.log"
  fi
fi

disk_pct=$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')
if [ "$disk_pct" -lt 80 ]; then
  ok "ดิสก์ใช้ไป ${disk_pct}%"
elif [ "$disk_pct" -lt 90 ]; then
  warn "ดิสก์ใช้ไป ${disk_pct}%: ลบ image เก่าด้วย docker image prune -f"
else
  bad "ดิสก์ใช้ไป ${disk_pct}% ใกล้เต็ม: docker image prune -f และย้ายไฟล์สำรองออก"
fi

echo
if [ "$errors" -eq 0 ]; then
  if [ "$warnings" -gt 0 ]; then echo "ระบบปกติ (คำเตือน $warnings ข้อ)"; else echo "ระบบปกติ"; fi
  exit 0
fi
echo "พบ $errors ข้อที่ต้องแก้ คำเตือน $warnings ข้อ"
exit 1
