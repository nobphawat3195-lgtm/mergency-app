{{flutter_js}}
{{flutter_build_config}}

// ไม่ลง flutter_service_worker.js: เว็บแอปช่างใช้ fixer_sw.js (ลงทะเบียนใน index.html)
// ซึ่งรับ Web Push และไม่ cache ไฟล์ ถ้าลงทั้งสองตัว ตัวหลังจะทับตัวแรกที่ scope เดียวกัน
_flutter.loader.load();
