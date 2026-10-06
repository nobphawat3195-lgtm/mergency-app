import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'offer_alarm.dart';

OfferAlarmBackend createOfferAlarmBackend() => _WebOfferAlarm();

/// เว็บใช้ Web Audio: เบราว์เซอร์ (โดยเฉพาะ iPhone) บล็อกเสียงจนกว่าผู้ใช้จะแตะจอ
/// จึงสร้าง AudioContext และเล่นเสียงเงียบตอนกด "พร้อมรับงาน" ไว้ก่อน งานเข้ามาทีหลังจะดังได้
class _WebOfferAlarm implements OfferAlarmBackend {
  web.AudioContext? _context;
  web.AudioBuffer? _buffer;
  web.AudioBufferSourceNode? _source;
  Future<void>? _loading;

  web.AudioContext _audio() => _context ??= web.AudioContext();

  @override
  bool get isInBackground => web.document.hidden;

  @override
  void unlock() {
    final context = _audio();
    unawaited(context.resume().toDart.then((_) {}, onError: (_) {}));
    final silent = context.createBufferSource()
      ..buffer = context.createBuffer(1, 1, 22050);
    silent.connect(context.destination);
    silent.start();
    _loading ??= _load();
  }

  Future<void> _load() async {
    final data = await rootBundle.load('assets/sounds/offer_alarm.wav');
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    _buffer = await _audio().decodeAudioData(bytes.buffer.toJS).toDart;
  }

  bool get _notificationSupported => web.window.has('Notification');

  @override
  void requestNotificationPermission() {
    if (!_notificationSupported) return;
    if (web.Notification.permission != 'default') return;
    unawaited(
      web.Notification.requestPermission().toDart.then((_) {}, onError: (_) {}),
    );
  }

  @override
  Future<void> startSound() async {
    final context = _audio();
    await (_loading ??= _load());
    final buffer = _buffer;
    if (buffer == null) return;
    await context.resume().toDart;
    _source?.stop();
    final source = context.createBufferSource()
      ..buffer = buffer
      ..loop = true;
    source.connect(context.destination);
    source.start();
    _source = source;
  }

  @override
  Future<void> stopSound() async {
    _source?.stop();
    _source = null;
  }

  @override
  void vibrate() {
    // iPhone (Safari) ไม่มี navigator.vibrate
    if (!web.window.navigator.has('vibrate')) return;
    web.window.navigator.vibrate([400.toJS, 200.toJS, 400.toJS].toJS);
  }

  @override
  Future<void> notify(String title, String body) async {
    if (!_notificationSupported || web.Notification.permission != 'granted') {
      return;
    }
    final options = web.NotificationOptions(
      body: body,
      tag: 'fixgo-offer',
      requireInteraction: true,
      icon: 'icons/Icon-192.png',
    );
    try {
      final notification = web.Notification(title, options);
      notification.onclick = ((web.Event _) {
        web.window.focus();
        notification.close();
      }).toJS;
    } catch (_) {
      // Chrome บน Android สร้าง Notification ตรงๆ ไม่ได้ ต้องผ่าน service worker
      final registration =
          await web.window.navigator.serviceWorker.getRegistration().toDart;
      await registration?.showNotification(title, options).toDart;
    }
  }
}
