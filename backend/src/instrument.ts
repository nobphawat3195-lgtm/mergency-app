// ต้อง import ไฟล์นี้ก่อนโมดูลอื่นใน main.ts เพื่อให้ Sentry ครอบ http/prisma ได้
import 'dotenv/config';
import * as Sentry from '@sentry/nestjs';

const dsn = process.env.SENTRY_DSN?.trim();

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.SENTRY_ENVIRONMENT ?? process.env.NODE_ENV,
    release: process.env.SENTRY_RELEASE,
    // ไม่เก็บข้อมูลผู้ใช้ cookie header query และ body (PDPA: มีเบอร์โทร OTP ที่อยู่)
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: false,
      httpBodies: [],
      urlQueryParams: false,
    },
    tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE ?? 0),
    beforeSend(event) {
      // ตัด body/header ทั้งหมด: อาจมีเบอร์โทร รหัส OTP ที่อยู่ หรือ Authorization
      if (event.request) {
        delete event.request.data;
        delete event.request.cookies;
        delete event.request.headers;
        delete event.request.query_string;
      }
      delete event.user;
      return event;
    },
  });
}
