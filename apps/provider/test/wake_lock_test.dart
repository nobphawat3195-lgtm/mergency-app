import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:fixgo_provider/wake_lock.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWakeLock implements ScreenWakeLock {
  final changes = <bool>[];

  @override
  bool get supported => true;

  @override
  void setEnabled(bool enabled) {
    if (changes.isEmpty || changes.last != enabled) changes.add(enabled);
  }
}

void main() {
  test('keeps the screen on only while signed in and online', () {
    final wakeLock = _FakeWakeLock();
    final api = FixGoApiClient(baseUrl: 'https://api.example.com')
      ..accessToken = 'token';
    final state = ProviderAppState(api: api, wakeLock: wakeLock);
    addTearDown(state.dispose);

    state.setOnline(true);
    expect(wakeLock.changes, [true]);
    state.setOnline(false);
    expect(wakeLock.changes, [true, false]);
    state.setOnline(true);
    // ออกจากระบบแล้วสถานะออนไลน์ค้างอยู่ ก็ต้องไม่กันจอดับ
    api.accessToken = null;
    state.setOnline(true);
    expect(wakeLock.changes, [true, false, true, false]);
  });

  test('the mobile app never holds a web wake lock', () {
    expect(createScreenWakeLock().supported, isFalse);
  });
}
