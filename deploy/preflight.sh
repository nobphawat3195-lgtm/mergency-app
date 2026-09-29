#!/usr/bin/env bash
# ตรวจเครื่องก่อนติดตั้ง: DNS ของทั้ง 4 ชื่อต้องชี้มาที่เครื่องนี้ก่อน Caddy ขอใบรับรอง HTTPS
# (Let's Encrypt จำกัดจำนวนครั้งที่ขอพลาด ถ้าชี้ผิดแล้วลองซ้ำหลายรอบจะโดนบล็อกชั่วคราว)
#
#   sudo bash deploy/preflight.sh fixgo.duckdns.org
#
# install.sh เรียกสคริปต์นี้เองหลังถามโดเมน
# exit 0 = พร้อม, 1 = มีข้อที่ต้องแก้ก่อน
# PREFLIGHT_PUBLIC_IP=<ip> ใช้แทนการถาม IP สาธารณะจากภายนอก (สำหรับทดสอบ)
set -uo pipefail

DOMAIN="${1:-}"
[ -n "$DOMAIN" ] || { echo "ใช้: sudo bash deploy/preflight.sh <โดเมนหลัก>" >&2; exit 2; }

errors=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; errors=$((errors + 1)); }

echo "ตรวจเครื่องก่อนติดตั้ง"

if [ "$(id -u)" -eq 0 ]; then ok "รันด้วยสิทธิ์ root"; else bad "ต้องรันด้วย sudo"; fi

mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$mem_mb" -ge 1800 ]; then
  ok "RAM ${mem_mb}MB"
else
  warn "RAM ${mem_mb}MB น้อยกว่า 2GB: ติดตั้งได้ (สคริปต์เพิ่ม swap ให้) แต่ build ครั้งแรกจะช้า"
fi

disk_gb=$(df -Pk / | awk 'NR==2 {print int($4/1024/1024)}')
if [ "$disk_gb" -ge 10 ]; then
  ok "พื้นที่ว่าง ${disk_gb}GB"
else
  bad "พื้นที่ว่างเหลือ ${disk_gb}GB ต้องมีอย่างน้อย 10GB (build image และไฟล์สำรอง)"
fi

# พอร์ต 80/443 ต้องว่าง ยกเว้นกรณีรันซ้ำที่ Caddy ของ FixGo ใช้อยู่แล้ว
port_holder() { # ชื่อโปรแกรมที่ฟังพอร์ต TCP นี้อยู่ ว่าง = ไม่มี
  if command -v ss >/dev/null 2>&1; then
    ss -Hltnp "sport = :$1" 2>/dev/null | grep -o 'users:(("[^"]*"' | head -1 | cut -d'"' -f2
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}'
  fi
}
for port in 80 443; do
  holder=$(port_holder "$port")
  if [ -z "$holder" ]; then
    ok "พอร์ต $port ว่าง"
  elif [[ "$holder" == docker* ]]; then
    ok "พอร์ต $port ใช้โดย Docker อยู่แล้ว (รันซ้ำ)"
  else
    bad "พอร์ต $port ถูกโปรแกรม $holder ใช้อยู่ ปิดก่อน เช่น sudo systemctl disable --now $holder"
  fi
done

if [ -n "${PREFLIGHT_PUBLIC_IP:-}" ]; then
  public_ip="$PREFLIGHT_PUBLIC_IP"
else
  public_ip=""
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    public_ip=$(curl -4 -fsS --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]')
    [[ "$public_ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && break
    public_ip=""
  done
fi

if [ -z "$public_ip" ]; then
  warn "หา IP สาธารณะของเครื่องไม่ได้ ข้ามการตรวจ DNS (ตรวจเองว่าโดเมนชี้มาที่เครื่องนี้)"
else
  ok "IP สาธารณะของเครื่อง $public_ip"
  for host in "$DOMAIN" "api.$DOMAIN" "admin.$DOMAIN" "fixer.$DOMAIN"; do
    resolved=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' | sed 's/ $//')
    if [ -z "$resolved" ]; then
      bad "$host ยังหาไม่เจอใน DNS"
    elif printf ' %s ' "$resolved" | grep -q " $public_ip "; then
      ok "$host ชี้มาที่เครื่องนี้"
    else
      bad "$host ชี้ไปที่ $resolved ไม่ใช่ $public_ip"
    fi
  done
  if [ "$errors" -gt 0 ] && [[ "$DOMAIN" == *.duckdns.org ]]; then
    echo
    echo "  DuckDNS: เข้า https://www.duckdns.org ใส่ $public_ip ในช่อง current ip ของ ${DOMAIN%%.duckdns.org} แล้วกด update ip"
    echo "  ชื่อย่อย api./admin./fixer. ใช้ IP เดียวกันอัตโนมัติ รอ 1-5 นาทีแล้วรันตรวจใหม่"
  fi
fi

echo
if [ "$errors" -eq 0 ]; then
  echo "พร้อมติดตั้ง"
  exit 0
fi
echo "พบ $errors ข้อที่ต้องแก้ก่อน"
echo "เปิด 80/443 ใน firewall ของผู้ให้บริการด้วย (เช่น Oracle Cloud: Security List) สคริปต์นี้ตรวจจากในเครื่องไม่ได้"
exit 1
