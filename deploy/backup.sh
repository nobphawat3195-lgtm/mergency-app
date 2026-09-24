#!/bin/sh
# สำรองฐานข้อมูลเป็นไฟล์ .sql.gz เก็บย้อนหลัง 14 วัน
# ตั้ง cron บนเครื่อง: 0 3 * * * /opt/fixgo/deploy/backup.sh >> /var/log/fixgo-backup.log 2>&1
# ควรคัดลอกโฟลเดอร์ backups ออกนอกเครื่องด้วย (เช่น rclone ไป R2/S3 อีก bucket)
set -eu
cd "$(dirname "$0")"
mkdir -p backups
file="backups/fixgo-$(date -u +%Y%m%d-%H%M%S).sql.gz"
docker compose -f docker-compose.yml --env-file .env.production exec -T db \
  pg_dump -U fixgo -d fixgo --no-owner --clean --if-exists | gzip > "$file"
# ไฟล์ว่าง = dump ล้มเหลว ห้ามลบของเก่า
[ -s "$file" ] || { echo "backup ว่างเปล่า: $file"; rm -f "$file"; exit 1; }
find backups -name 'fixgo-*.sql.gz' -mtime +14 -delete
echo "สำรองแล้ว: $file"
