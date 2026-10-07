import 'dart:async';

import 'package:flutter/services.dart';

import 'offer_alarm_io.dart' if (dart.library.js_interop) 'offer_alarm_web.dart'
    as platform;

/// เสียงพูดตอนงานเข้า แก้ข้อความที่นี่ที่เดียว (ใช้ทั้งแอปมือถือและเว็บ)
const offerVoiceText = 'มีงานเข้าแล้ว ออกหาเงินกัน!';

/// ภาษาของเสียงสังเคราะห์ (TTS) เครื่องไม่มีเสียงภาษานี้จะเล่นแค่เสียงปลุก
const offerVoiceLanguage = 'th-TH';

/// ไฟล์เสียงพูดที่อัดเอง วางไฟล์นี้ในแอปแล้วจะเล่นแทนเสียงสังเคราะห์ (TTS) อัตโนมัติ
const offerVoiceAsset = 'assets/sounds/offer_voice.mp3';

/// มีไฟล์ [offerVoiceAsset] ในแอปไหม (โฟลเดอร์ assets/sounds/ ถูกรวมทั้งโฟลเดอร์อยู่แล้ว)
Future<bool> hasOfferVoiceAsset([AssetBundle? bundle]) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(
      bundle ?? rootBundle,
    );
    return manifest.listAssets().contains(offerVoiceAsset);
  } catch (_) {
    return false;
  }
}

/// ส่วนที่ต่างกันระหว่างแอปมือถือกับเว็บ (เสียง เสียงพูด สั่น แจ้งเตือนของระบบ)
abstract class OfferAlarmBackend {
  /// เรียกตอนผู้ใช้แตะจอเท่านั้น (เว็บบล็อกเสียงและเสียงพูดจนกว่าจะมีการแตะ) ต้องทำงานแบบ sync
  void unlock();

  /// ขออนุญาตแจ้งเตือน เรียกตอนผู้ใช้แตะจอ (Safari ไม่ให้ขอนอก gesture)
  void requestNotificationPermission();

  /// แอปอยู่เบื้องหลัง (เว็บ: แท็บถูกซ่อน)
  bool get isInBackground;

  /// เริ่มเล่นเสียงปลุก 1 ครั้ง (ไม่วน) คืนค่าทันทีที่เริ่มเล่น
  Future<void> playChime();

  /// พูด [text] (หรือเล่นไฟล์ [offerVoiceAsset] ถ้ามี) คืนค่าเมื่อพูดจบ
  /// เครื่องไม่มีเสียงภาษาไทยให้คืนค่าทันทีโดยไม่พูด
  Future<void> speak(String text);

  /// หยุดทั้งเสียงปลุกและเสียงพูดที่ค้างอยู่
  Future<void> stopSound();
  void vibrate();
  Future<void> notify(String title, String body);
}

/// เสียงปลุกตอนมีงานใหม่: ต่อรอบเล่นเสียงปลุก ~1.5 วิ แล้วพูด [offerVoiceText]
/// วนทุก ~4 วิ และสั่นทุก 1.5 วิ จนกว่าจะเรียก [stop]
/// แอปอยู่เบื้องหลังจะแสดงแจ้งเตือนของระบบด้วย
///
/// ทุกคำสั่งไม่ throw: เล่นเสียงไม่ได้ (เบราว์เซอร์บล็อก ไม่มีลำโพง) งานยังเด้งในหน้าจอตามปกติ
class OfferAlarm {
  OfferAlarm([OfferAlarmBackend? backend])
      : _backend = backend ?? platform.createOfferAlarmBackend();

  /// ความยาวหนึ่งรอบ (เสียงปลุก + เสียงพูด) ก่อนเริ่มรอบถัดไป
  static const cycle = Duration(seconds: 4);

  /// ช่วงของเสียงปลุกก่อนเริ่มพูด
  static const chimeLength = Duration(milliseconds: 1500);

  /// รอเสียงพูดนานสุดเท่านี้ (กันเครื่องที่ไม่ส่งสัญญาณว่าพูดจบ)
  static const maxSpeech = Duration(seconds: 4);

  final OfferAlarmBackend _backend;
  Timer? _vibration;
  bool _ringing = false;

  /// เพิ่มทุกครั้งที่เริ่ม/หยุด รอบที่ค้างจากครั้งก่อนจะรู้ว่าไม่ใช่ของตัวเองแล้วเลิก
  int _generation = 0;
  final Map<Timer, Completer<void>> _waits = {};

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
    unawaited(_play(_start(), repeat: true));
  }

  Future<void> stop() async {
    _generation++;
    _vibration?.cancel();
    _vibration = null;
    _cancelWaits();
    if (!_ringing) return;
    _ringing = false;
    await _guardAsync(_backend.stopSound);
  }

  /// ปุ่ม "ทดสอบเสียงแจ้งเตือน": เรียกจากการแตะจอ เล่นชุดเดียวกับตอนงานเข้า 1 รอบแล้วหยุดเอง
  Future<void> test() async {
    prepare();
    if (_ringing) return;
    final generation = _start();
    await _play(generation, repeat: false);
    if (generation == _generation) await stop();
  }

  void dispose() {
    unawaited(stop());
  }

  int _start() {
    _ringing = true;
    _guard(_backend.vibrate);
    _vibration = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _guard(_backend.vibrate),
    );
    return ++_generation;
  }

  /// เสียงปลุก -> รอ [chimeLength] -> พูด -> รอให้ครบ [cycle] แล้ววนใหม่
  Future<void> _play(int generation, {required bool repeat}) async {
    bool current() => _ringing && generation == _generation;
    while (current()) {
      final cycleEnd = _wait(cycle);
      await _guardAsync(_backend.playChime);
      await _wait(chimeLength);
      if (!current()) return;
      await Future.any([
        _guardAsync(() => _backend.speak(offerVoiceText)),
        _wait(maxSpeech),
      ]);
      if (!repeat || !current()) return;
      await cycleEnd;
    }
  }

  /// รอแบบที่ [stop] ยกเลิกได้ทันที (ไม่ทิ้ง timer ค้างหลังหยุดปลุก)
  Future<void> _wait(Duration duration) {
    final done = Completer<void>();
    late final Timer timer;
    timer = Timer(duration, () {
      _waits.remove(timer);
      done.complete();
    });
    _waits[timer] = done;
    return done.future;
  }

  void _cancelWaits() {
    final waits = Map.of(_waits);
    _waits.clear();
    for (final entry in waits.entries) {
      entry.key.cancel();
      if (!entry.value.isCompleted) entry.value.complete();
    }
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
