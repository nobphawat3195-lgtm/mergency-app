import 'wake_lock_stub.dart' if (dart.library.js_interop) 'wake_lock_web.dart'
    as platform;

/// กันจอดับระหว่างช่างเปิด "พร้อมรับงาน" บนเว็บ (Screen Wake Lock API)
///
/// เบราว์เซอร์ปล่อย wake lock เองเมื่อสลับแอป/ล็อกจอ จึงขอใหม่ทุกครั้งที่กลับมาที่หน้านี้
/// แอปมือถือไม่ใช้ (stub ไม่ทำอะไร) เพราะ push ของระบบปลุกเครื่องได้อยู่แล้ว
abstract class ScreenWakeLock {
  /// เบราว์เซอร์นี้รองรับ wake lock หรือไม่
  bool get supported;

  /// true = ขอให้จอเปิดค้าง, false = ปล่อย
  void setEnabled(bool enabled);
}

ScreenWakeLock createScreenWakeLock() => platform.createScreenWakeLock();
