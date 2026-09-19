# 5. โครงสร้างข้อมูลหลัก (Data Model)

โครงร่างระดับ entity สำหรับออกแบบฐานข้อมูล (Postgres/Firestore ก็ปรับใช้ได้)

## Core Entities

```
User (ลูกค้า)
├── id, name, phone, email, avatar
├── addresses[] (บ้าน, ที่ทำงาน, ล่าสุด)
└── vehicles[] (รถของตัวเอง — ใช้ผูกกับงานฉุกเฉิน)

Provider (ผู้ให้บริการ — ใช้ร่วมกัน 2 role)
├── id, name, phone, avatar, rating_avg
├── role: enum [mechanic, tow_driver, inspector]
├── verification_status: enum [pending, verified, suspended]
├── certifications[] (สำคัญมากสำหรับ inspector — ต้องมีเอกสาร/ใบรับรอง)
├── service_area (รัศมี/จังหวัดที่รับงาน)
└── current_location (lat, lng, updated_at)

ServiceCategory (หมวดบริการ)
├── id, name, icon, type: enum [emergency, inspection]
└── sub_services[] → SubService

SubService
├── id, category_id, name, description
├── base_price, price_type: enum [call_out_fee, full_service]
└── vehicle_type_multiplier{} (เก๋ง/SUV/กระบะ ราคาต่างกัน)

Order (งานฉุกเฉิน)
├── id, user_id, provider_id (nullable จนกว่าจะ match)
├── category_id, sub_service_id, vehicle_type
├── status: enum [searching, matched, en_route, in_progress, completed, cancelled]
├── location (pickup point)
├── price_estimated, price_final
├── created_at, matched_at, completed_at
└── rating, review_text

InspectionBooking (งานตรวจรถมือสอง)
├── id, user_id, inspector_id (nullable จนกว่าจะ match)
├── package: enum [basic, full]
├── vehicle_info { brand, model, year, mileage, seller_type }
├── appointment_location, appointment_datetime
├── status: enum [pending, confirmed, in_progress, report_ready, completed, cancelled]
├── deposit_paid, total_price
└── report_id → InspectionReport

InspectionReport
├── id, booking_id
├── overall_score (0-100)
├── sections[] → InspectionSection
├── summary_recommendation (text)
├── pdf_url
└── generated_at

InspectionSection
├── id, report_id
├── category: enum [engine, suspension, electrical, body, interior, documents]
├── score: enum [good, fair, caution, problem]
├── notes (text)
└── media[] (photo/video urls)

Payment
├── id, order_id / booking_id
├── amount, method: enum [card, promptpay, wallet]
├── status: enum [pending, paid, refunded]
└── transaction_ref

ChatMessage (ระหว่าง user-provider หรือ user-AI assistant)
├── id, conversation_id, sender_type, content, created_at
```

## จุดที่ต้องคิดเรื่อง business logic เพิ่มเติมภายหลัง

- ระบบ matching/dispatch: ใช้ geo-query (PostGIS หรือ Firestore GeoQuery) หาผู้ให้บริการที่ว่างใกล้ที่สุดก่อน
- ระบบ commission: แอปหักค่าคอมมิชชันจากผู้ให้บริการเท่าไหร่ต่องาน
- ระบบ escrow สำหรับเงินมัดจำ inspection (กันข้อพิพาท ผู้ขายรถยกเลิกนัดกะทันหัน)
