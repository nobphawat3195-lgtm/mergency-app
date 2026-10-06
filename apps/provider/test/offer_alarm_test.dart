import 'package:fake_async/fake_async.dart';
import 'package:fixgo_provider/offer_alarm.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAlarmBackend implements OfferAlarmBackend {
  final calls = <String>[];
  bool background = false;
  bool failSound = false;

  @override
  bool get isInBackground => background;
  @override
  void unlock() => calls.add('unlock');
  @override
  void requestNotificationPermission() => calls.add('permission');
  @override
  Future<void> startSound() async {
    calls.add('start');
    if (failSound) throw StateError('blocked');
  }

  @override
  Future<void> stopSound() async => calls.add('stop');
  @override
  void vibrate() => calls.add('vibrate');
  @override
  Future<void> notify(String title, String body) async =>
      calls.add('notify:$title');
}

void main() {
  test('rings once with looping sound and repeated vibration until stopped',
      () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.ring();
      alarm.ring(); // งานที่สองระหว่างปลุก ไม่เริ่มเสียงซ้ำ
      async.elapse(const Duration(seconds: 4));
      expect(alarm.isRinging, true);
      expect(backend.calls.where((c) => c == 'start'), hasLength(1));
      expect(backend.calls.where((c) => c == 'vibrate').length, 3);
      alarm.stop();
      async.flushMicrotasks();
      expect(alarm.isRinging, false);
      expect(backend.calls.last, 'stop');
      final vibrations = backend.calls.where((c) => c == 'vibrate').length;
      async.elapse(const Duration(seconds: 5));
      expect(backend.calls.where((c) => c == 'vibrate').length, vibrations);
    });
  });

  test('shows a system notification only when the app is in the background',
      () async {
    final backend = FakeAlarmBackend();
    final alarm = OfferAlarm(backend);
    await alarm.ring();
    expect(backend.calls, isNot(contains('notify:มีงานใหม่ใกล้คุณ')));
    await alarm.stop();
    backend.background = true;
    await alarm.ring();
    expect(backend.calls, contains('notify:มีงานใหม่ใกล้คุณ'));
    await alarm.stop();
  });

  test('prepare unlocks sound and asks for notifications', () {
    final backend = FakeAlarmBackend();
    OfferAlarm(backend).prepare();
    expect(backend.calls, ['unlock', 'permission']);
  });

  test('a blocked sound never throws', () async {
    final backend = FakeAlarmBackend()..failSound = true;
    final alarm = OfferAlarm(backend);
    await alarm.ring();
    expect(alarm.isRinging, true);
    await alarm.stop();
  });

  test('test button plays briefly then stops by itself', () {
    fakeAsync((async) {
      final backend = FakeAlarmBackend();
      final alarm = OfferAlarm(backend);
      alarm.test(duration: const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(backend.calls.take(3), ['unlock', 'permission', 'vibrate']);
      expect(alarm.isRinging, true);
      async.elapse(const Duration(seconds: 3));
      expect(alarm.isRinging, false);
    });
  });
}
