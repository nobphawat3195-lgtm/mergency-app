import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'wake_lock.dart';

ScreenWakeLock createScreenWakeLock() => _WebWakeLock();

class _WebWakeLock implements ScreenWakeLock {
  bool _wanted = false;
  bool _listening = false;
  JSObject? _sentinel;

  @override
  bool get supported => web.window.navigator.has('wakeLock');

  @override
  void setEnabled(bool enabled) {
    if (_wanted == enabled) return;
    _wanted = enabled;
    if (enabled) {
      _listenVisibility();
      unawaited(_acquire());
    } else {
      _release();
    }
  }

  void _listenVisibility() {
    if (_listening) return;
    _listening = true;
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (_wanted && web.document.visibilityState == 'visible') {
          unawaited(_acquire());
        }
      }).toJS,
    );
  }

  bool get _held {
    final sentinel = _sentinel;
    if (sentinel == null) return false;
    return !(sentinel.getProperty<JSBoolean?>('released'.toJS)?.toDart ??
        false);
  }

  Future<void> _acquire() async {
    if (!supported || _held || web.document.visibilityState != 'visible') {
      return;
    }
    try {
      final wakeLock = web.window.navigator.getProperty<JSObject>(
        'wakeLock'.toJS,
      );
      final sentinel = await wakeLock
          .callMethod<JSPromise<JSObject>>('request'.toJS, 'screen'.toJS)
          .toDart;
      // ช่างปิดรับงานระหว่างรอ: ปล่อยทันที
      if (!_wanted) {
        sentinel.callMethod<JSAny?>('release'.toJS);
        return;
      }
      _sentinel = sentinel;
    } catch (_) {
      // แบตต่ำ/โหมดประหยัดพลังงาน เบราว์เซอร์ปฏิเสธได้ ไม่ใช่ error ที่ต้องแจ้งช่าง
    }
  }

  void _release() {
    final sentinel = _sentinel;
    _sentinel = null;
    if (sentinel == null) return;
    try {
      sentinel.callMethod<JSAny?>('release'.toJS);
    } catch (_) {}
  }
}
