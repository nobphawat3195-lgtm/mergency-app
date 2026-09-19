# 7. Roadmap เป็นเฟส

## Phase 0 — Validate (2-3 สัปดาห์)
- ทำ clickable prototype (Figma) จาก spec นี้ ให้คนทดลองใช้จริงก่อนลงทุนเขียนโค้ด
- สัมภาษณ์/สำรวจกลุ่มเป้าหมายจริง 10-20 คน เรื่องราคาที่ยอมจ่ายสำหรับบริการตรวจรถ

## Phase 1 — MVP Emergency (4-6 สัปดาห์)
- Auth, Home, Emergency booking flow (ไม่มี auto-matching อัตโนมัติ ใช้ admin จับคู่ก่อน)
- Payment พื้นฐาน
- Provider app เวอร์ชันง่าย (รับ-ปฏิเสธงาน, อัปเดตสถานะ)

## Phase 2 — Real-time & Scale Emergency (4 สัปดาห์)
- Auto dispatch/matching ตามระยะทาง
- Real-time tracking เต็มรูปแบบ
- Rating/review system

## Phase 3 — Inspection Feature (6-8 สัปดาห์)
- Inspection booking flow เต็มรูปแบบ
- Digital checklist ฝั่ง Provider app
- Report generation (scorecard + PDF)
- ระบบรับรอง inspector (verification workflow)

## Phase 4 — Growth
- นินา AI ผู้ช่วย (chatbot ให้คำแนะนำเบื้องต้นก่อนตัดสินใจเรียกบริการ)
- สั่งอะไหล่ (marketplace เชื่อมร้านอะไหล่)
- Loyalty/subscription plan สำหรับลูกค้าเรียกบ่อย

## Metric ที่ควรติดตามตั้งแต่ MVP

- Emergency: เวลาเฉลี่ยตั้งแต่กดเรียกถึงช่างมาถึง (time-to-arrival), % งานที่ไม่มีช่างรับ
- Inspection: % ลูกค้าที่ตัดสินใจซื้อ/ไม่ซื้อหลังได้รายงาน, NPS ของรายงาน
- ทั่วไป: repeat usage rate, churn ของ provider
