import 'dart:async';

import 'offer_alarm_io.dart' if (dart.library.js_interop) 'offer_alarm_web.dart'
    as platform;

/// ส่วนที่ต่างกันระหว่างแอปมือถือกับเว็บ (เสียง สั่น แจ้งเตือนของระบบ)
abstract class OfferAlarmBackend {
  /// เรียกตอนผู้ใช้แตะจอเท่านั้น (เว็บบล็อกเสียงจนกว่าจะมีการแตะ) ต้องทำงานแบบ sync
  void unlock();

  /// ขออนุญาตแจ้งเตือน เรียกตอนผู้ใช้แตะจอ (Safari ไม่ให้ขอนอก gesture)
  void requestNotificationPermission();

  /// แอปอยู่เบื้องหลัง (เว็บ: แท็บถูกซ่อน)
  bool get isInBackground;

  Future<void> startSound();
  Future<void> stopSound();
  void vibrate();
  Future<void> notify(String title, String body);
}

/// เสียงปลุกตอนมีงานใหม่: เสียงวนซ้ำ + สั่นทุก 1.5 วินาที จนกว่าจะเรียก [stop]
/// แอปอยู่เบื้องหลังจะแสดงแจ้งเตือนของระบบด้วย
///
/// ทุกคำสั่งไม่ throw: เล่นเสียงไม่ได้ (เบราว์เซอร์บล็อก ไม่มีลำโพง) งานยังเด้งในหน้าจอตามปกติ
class OfferAlarm {
  OfferAlarm([OfferAlarmBackend? backend])
      : _backend = backend ?? platform.createOfferAlarmBackend();

  final OfferAlarmBackend _backend;
  Timer? _vibration;
  Timer? _testStop;
  bool _ringing = false;

  bool get isRinging => _ringing;

  /// ตอนช่างกดเปิด "พร้อมรับงาน": ปลดล็อกเสียงของเบราว์เซอร์และขออนุญาตแจ้งเตือน
  void prepare() {
    _guard(_backend.unlock);
    _guard(_backend.requestNotificationPermission);
  }

  /// เริ่มปลุก ถ้าปลุกอยู่แล้วแค่แจ้งเตือนเพิ่ม (กรณีงานใหม่เข้ามาซ้อน)
  Future<void> ring({String title = 'มีงานใหม่ใกล้คุณ', String? body}) async {
    if (_backend.isInBackground) {
      await _guardAsync(
        () => _backend.notify(title, body ?? 'เปิดแอปเพื่อกดรับงานก่อนหมดเวลา'),
      );
    }
    if (_ringing) return;
    _ringing = true;
    _testStop?.cancel();
    _guard(_backend.vibrate);
    _vibration = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _guard(_backend.vibrate),
    );
    await _guardAsync(_backend.startSound);
  }

  Future<void> stop() async {
    _testStop?.cancel();
    _vibration?.cancel();
    _vibration = null;
    if (!_ringing) return;
    _ringing = false;
    await _guardAsync(_backend.stopSound);
  }

  /// ปุ่ม "ทดสอบเสียงแจ้งเตือน": เรียกจากการแตะจอ เล่นสักครู่แล้วหยุดเอง
  Future<void> test({Duration duration = const Duration(seconds: 4)}) async {
    prepare();
    await ring();
    _testStop?.cancel();
    _testStop = Timer(duration, () => unawaited(stop()));
  }

  void dispose() {
    unawaited(stop());
  }

  static void _guard(void Function() action) {
    try {
      action();
    } catch (_) {}
  }

  static Future<void> _guardAsync(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }
}
