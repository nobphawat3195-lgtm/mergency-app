import 'browser_url_stub.dart'
    if (dart.library.js_interop) 'browser_url_web.dart' as impl;

/// query string ของหน้าเว็บตอนเปิด (มือถือได้ค่าว่าง)
Map<String, String> browserQueryParameters() => impl.browserQueryParameters();

/// ลบ query string ออกจากแถบที่อยู่โดยไม่โหลดหน้าใหม่ เช่น ตั๋วล็อกอินที่ใช้ไปแล้ว
void clearBrowserQuery() => impl.clearBrowserQuery();
