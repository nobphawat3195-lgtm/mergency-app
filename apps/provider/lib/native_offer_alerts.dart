import 'native_offer_alerts_stub.dart'
    if (dart.library.io) 'native_offer_alerts_io.dart' as platform;

/// ช่างกดอะไรบนแจ้งเตือนงานใหม่ของระบบ (แอปมือถือ)
class OfferAlertAction {
  const OfferAlertAction({required this.orderId, required this.kind});

  final String orderId;
  final OfferAlertActionKind kind;
}

enum OfferAlertActionKind {
  /// แตะตัวแจ้งเตือน หรือระบบเปิดแอปแบบเต็มจอ: แสดงจอปลุกในแอป
  open,

  /// ปุ่ม "รับงาน"
  accept,

  /// ปุ่ม "ปฏิเสธ" (ตอนแอปเปิดอยู่ ถ้าแอปปิดอยู่ส่งปฏิเสธจากเบื้องหลังเอง)
  reject,
}

/// สิ่งที่ต้องอนุญาตให้แจ้งเตือนงานใหม่ดังตอนล็อกจอ (null = ไม่เกี่ยวกับเครื่องนี้)
class AlarmReadiness {
  const AlarmReadiness({
    this.notifications,
    this.fullScreen,
    this.batteryUnrestricted,
  });

  final bool? notifications;
  final bool? fullScreen;
  final bool? batteryUnrestricted;

  /// ยังมีข้อที่ต้องแก้ (ใช้แสดงการ์ดเตือนในหน้าหลัก)
  bool get needsAttention =>
      notifications == false ||
      fullScreen == false ||
      batteryUnrestricted == false;
}

enum AlarmSetting { notifications, fullScreen, battery, appDetails }

/// แจ้งเตือนงานใหม่แบบนาฬิกาปลุกของแอปมือถือ (Android: เต็มจอ เสียงวน ปุ่มรับ/ปฏิเสธ)
///
/// เว็บไม่ใช้ (stub ไม่ทำอะไร) เว็บใช้ Web Push และเสียงปลุกในหน้า
abstract class NativeOfferAlerts {
  static NativeOfferAlerts create() => platform.createNativeOfferAlerts();

  /// เรียกครั้งเดียวตอนเปิดแอป หลัง PushNotifications.init
  Future<void> init();

  /// ปุ่ม/การแตะบนแจ้งเตือนตอนแอปเปิดอยู่
  Stream<OfferAlertAction> get actions;

  /// แจ้งเตือนที่ทำให้แอปเปิดขึ้นจากสถานะปิด อ่านได้ครั้งเดียว
  OfferAlertAction? takeLaunchAction();

  /// หยุดเสียงและลบแจ้งเตือนของงานนี้
  Future<void> cancel(String orderId);

  /// แอปกลับมาอยู่หน้าจอ: เสียงปลุกในแอปทำงานแทน ไม่ให้ดังซ้อนกัน
  Future<void> cancelAll();

  /// แจ้งเตือนตัวอย่างใน 5 วิ ให้ช่างลองล็อกจอแล้วฟังเสียงจริง
  Future<void> showTest();

  Future<AlarmReadiness> readiness();

  Future<void> openSetting(AlarmSetting setting);
}
