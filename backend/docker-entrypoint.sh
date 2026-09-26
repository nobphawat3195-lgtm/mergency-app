#!/bin/sh
# รัน migration ที่ยังไม่ได้รันก่อนเปิด API ทุกครั้ง (migrate deploy ไม่แก้ schema เอง ไม่ลบข้อมูล)
set -e
if [ "${SKIP_MIGRATIONS:-false}" != "true" ]; then
  npx prisma migrate deploy
fi
exec "$@"
