import 'wake_lock.dart';

ScreenWakeLock createScreenWakeLock() => _NoWakeLock();

class _NoWakeLock implements ScreenWakeLock {
  @override
  bool get supported => false;

  @override
  void setEnabled(bool enabled) {}
}
