import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fixgo_provider/offer_alarm.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAlarmBackend implements OfferAlarmBackend {
  final calls = <String>[];
  bool background = false;
  bool failSound = false;

  /// เวลาที่ใช้พูด (null = ไม่ส่งสัญญาณพูดจบเลย)
  Duration? speechLength = const Duration(seconds: 2);

  @override
  bool get isInBackground => background;
  @override
  void unlock() => calls.add('unlock');
  @override
  void requestNotificationPermission() => calls.add('permission');
  @override
  Future<void> playChime() async {
    calls.add('chime');
    if (failSound) throw StateError('blocked');
  }

  @override
  Future<void> speak(String text) {
    calls.add('speak:$text');
    if (failSound) throw StateError('blocked');
    final length = speechLength;
    if (length == null) return Completer<void>().future;
    return Future.delayed(length, () => calls.add('spoken'));
  }

  @override
  Future<void> stopSound() async => calls.add('stop');
  @override
  void vibrate() => calls.add('vibrate');
  @override
  Future<void> notify(String title, String body) async =>
      calls.add('notify:$title');

  List<String> get sounds =>
      calls.where((c) => c == 'chime' || c.startsWith('speak:')).toList();
}

const _speak = 'speak:$offerVoiceText';

void main() {
  test('chimes every 4 seconds and speaks the Thai voice every 3rd round', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring();
      alarm.ring(); // งานที่สองระหว่างปลุก ไม่เริ่มรอบซ้อน
      async.flushMicrotasks();
      expect(backend.sounds, ['chime']);

      // เสียงปลุก 1.5 วิ แล้วค่อยพูด
      async.elapse(const Duration(milliseconds: 1400));
      expect(backend.sounds, ['chime']);
      async.elapse(const Duration(milliseconds: 200));
      expect(backend.sounds, ['chime', _speak]);

      // รอบ 2 และ 3 (4 วิ, 8 วิ) ดังแค่เสียงปลุก
      async.elapse(const Duration(milliseconds: 2500));
      expect(backend.sounds, ['chime', _speak, 'chime']);
      async.elapse(const Duration(seconds: 4));
      expect(backend.sounds, ['chime', _speak, 'chime', 'chime']);

      // รอบ 4 (12 วิ) พูดอีกครั้ง
      async.elapse(const Duration(seconds: 4));
      async.elapse(const Duration(milliseconds: 1600));
      expect(
        backend.sounds,
        ['chime', _speak, 'chime', 'chime', 'chime', _speak],
      );
      expect(alarm.isRinging, true);
      alarm.stop();
    });
  });

  test('never rings past the offer expiry, even if nobody calls stop', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring(until: clock.now().add(const Duration(seconds: 10)));
      async.elapse(const Duration(seconds: 9));
      expect(alarm.isRinging, true);
      async.elapse(const Duration(seconds: 2));
      expect(alarm.isRinging, false);
      expect(backend.calls.last, 'stop');
      final before = backend.sounds.length;
      async.elapse(const Duration(seconds: 20));
      expect(backend.sounds.length, before);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a second offer extends the alarm to its own expiry', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring(until: clock.now().add(const Duration(seconds: 5)));
      alarm.ring(until: clock.now().add(const Duration(seconds: 20)));
      async.elapse(const Duration(seconds: 10));
      expect(alarm.isRinging, true);
      async.elapse(const Duration(seconds: 11));
      expect(alarm.isRinging, false);
    });
  });

  test('an offer that already expired does not ring at all', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring(until: clock.now().subtract(const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 5));
      expect(alarm.isRinging, false);
      expect(backend.sounds, isEmpty);
    });
  });

  test('stop silences everything and no cycle or vibration continues', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring();
      async.elapse(const Duration(seconds: 2)); // กำลังพูดอยู่
      alarm.stop();
      async.flushMicrotasks();
      expect(alarm.isRinging, false);
      expect(backend.calls.last, 'stop');
      final before = backend.calls.length;
      async.elapse(const Duration(seconds: 12));
      expect(
        backend.calls.skip(before).where((c) => c != 'spoken'),
        isEmpty,
      );
      expect(async.pendingTimers.where((t) => t.isPeriodic), isEmpty);
    });
  });

  test('a long voice delays the next cycle instead of overlapping', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend()
        ..speechLength = const Duration(seconds: 3);
      final alarm = OfferAlarm(backend);
      alarm.ring();
      // พูดเริ่ม 1.5 วิ จบ 4.5 วิ รอบถัดไปเริ่มหลังพูดจบ
      async.elapse(const Duration(milliseconds: 4400));
      expect(backend.sounds, ['chime', _speak]);
      async.elapse(const Duration(milliseconds: 200));
      expect(backend.sounds, ['chime', _speak, 'chime']);
      alarm.stop();
    });
  });

  test('a voice that never reports the end does not stall the alarm', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend()..speechLength = null;
      final alarm = OfferAlarm(backend);
      alarm.ring();
      async.elapse(const Duration(seconds: 6));
      expect(backend.sounds, ['chime', _speak, 'chime']);
      alarm.stop();
    });
  });

  test('shows a system notification only when the app is in the background',
      () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring();
      async.flushMicrotasks();
      expect(backend.calls, isNot(contains('notify:มีงานใหม่ใกล้คุณ')));
      alarm.stop();
      backend.background = true;
      alarm.ring();
      async.flushMicrotasks();
      expect(backend.calls, contains('notify:มีงานใหม่ใกล้คุณ'));
      alarm.stop();
    });
  });

  test('prepare unlocks sound and asks for notifications', () {
    final backend = FakeAlarmBackend();
    OfferAlarm(backend).prepare();
    expect(backend.calls, ['unlock', 'permission']);
  });

  test('a blocked sound never throws and keeps cycling', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend()..failSound = true;
      final alarm = OfferAlarm(backend);
      alarm.ring();
      async.elapse(const Duration(seconds: 5));
      expect(alarm.isRinging, true);
      expect(backend.sounds, ['chime', _speak, 'chime']);
      alarm.stop();
    });
  });

  test('test button plays one chime + voice then stops by itself', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.test();
      async.flushMicrotasks();
      expect(
        backend.calls.take(4),
        ['unlock', 'permission', 'vibrate', 'chime'],
      );
      expect(alarm.isRinging, true);
      async.elapse(const Duration(milliseconds: 3400));
      expect(alarm.isRinging, true);
      async.elapse(const Duration(milliseconds: 200));
      expect(alarm.isRinging, false);
      expect(backend.sounds, ['chime', _speak]);
      async.elapse(const Duration(seconds: 8));
      expect(backend.sounds, ['chime', _speak]);
    });
  });

  test('the test button does not cut a real alarm short', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring();
      alarm.test();
      async.elapse(const Duration(seconds: 5));
      expect(alarm.isRinging, true);
      expect(backend.sounds, ['chime', _speak, 'chime']);
      alarm.stop();
    });
  });

  group('recorded voice file', () {
    test('is used when present in the asset manifest', () async {
      expect(await hasOfferVoiceAsset(_Bundle([offerVoiceAsset])), true);
    });

    test('falls back to TTS when missing', () async {
      expect(
        await hasOfferVoiceAsset(_Bundle(['assets/sounds/offer_alarm.wav'])),
        false,
      );
    });
  });
}

/// AssetBundle ที่มีแค่ AssetManifest.bin ตามรายชื่อไฟล์ที่ให้
class _Bundle extends CachingAssetBundle {
  _Bundle(this.assets);

  final List<String> assets;

  @override
  Future<ByteData> load(String key) async {
    if (key != 'AssetManifest.bin') throw StateError('missing $key');
    return const StandardMessageCodec().encodeMessage({
      for (final asset in assets)
        asset: [
          {'asset': asset},
        ],
    })!;
  }
}
