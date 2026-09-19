# 6. Tech Stack และสถาปัตยกรรมที่แนะนำ

## Mobile App (Customer + Provider)

- **Framework**: Flutter (แนะนำมากกว่า React Native สำหรับ use case นี้ เพราะ performance ของแผนที่ real-time + animation ลื่นกว่า และ maintain 2 แอปจาก 1 codebase ได้ง่าย)
  - ทางเลือก: React Native + Expo ถ้าทีมถนัด JS/TS มากกว่า
- **State management**: Riverpod (Flutter) หรือ Redux Toolkit (RN)
- **Map**: Google Maps SDK (ครอบคลุม/แม่นยำที่สุดในไทย)

## Backend

- **API**: NestJS (Node/TypeScript) หรือ Django REST — เลือกตามทีม
- **Database**: PostgreSQL + PostGIS extension (สำหรับ geo-query หา provider ใกล้ที่สุด)
- **Real-time**: WebSocket (Socket.io) สำหรับ tracking ตำแหน่งช่าง/สถานะงาน
- **File storage**: S3-compatible (รูป/วิดีโอ inspection report ต้องเก็บปริมาณมาก)
- **Push notification**: Firebase Cloud Messaging (ใช้ได้ทั้ง iOS/Android)
- **Payment**: Omise หรือ 2C2P (รองรับพร้อมเพย์ + บัตรในไทย)

## Infra เบื้องต้น (MVP)

```
Mobile App (Flutter) ──► API Gateway (NestJS)
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        PostgreSQL      Redis (cache/       S3 (media)
        + PostGIS        matching queue)
              │
              ▼
        WebSocket Server (tracking real-time)
```

## เหตุผลที่ต้องมี Backend แยก (ไม่ทำแบบ serverless ล้วน)

Dispatch/matching logic (หาช่างใกล้ที่สุดที่ว่างจริง, จัดคิว, timeout ขยายรัศมี) มี state ซับซ้อนกว่าที่ Firebase/Supabase ตรงๆ จะจัดการสะดวก — แนะนำเขียน matching service เป็น backend เฉพาะ แม้ส่วนอื่น (auth, chat) จะใช้ managed service ก็ได้

## ลำดับการพัฒนา MVP ที่แนะนำ

1. Auth + User/Provider profile
2. Emergency flow แบบไม่มี real-time matching ก่อน (admin manual assign) — เพื่อ validate business ก่อนลงทุนระบบ dispatch อัตโนมัติ
3. Payment integration
4. Real-time tracking + auto matching
5. Inspection flow (ทำทีหลัง เพราะ operationally ซับซ้อนกว่า ต้องมี inspector ที่ผ่านการรับรองก่อน)
