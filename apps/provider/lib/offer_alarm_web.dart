import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'offer_alarm.dart';

OfferAlarmBackend createOfferAlarmBackend() => _WebOfferAlarm();

/// เว็บใช้ Web Audio + Web Speech: เบราว์เซอร์ (โดยเฉพาะ iPhone) บล็อกเสียงและเสียงพูด
/// จนกว่าผู้ใช้จะแตะจอ จึงสร้าง AudioContext เล่นเสียงเงียบ และพูดข้อความเงียบ
/// ตอนกด "พร้อมรับงาน" ไว้ก่อน งานเข้ามาทีหลังจะดังได้
class _WebOfferAlarm implements OfferAlarmBackend {
  web.AudioContext? _context;
  web.AudioBuffer? _chime;
  web.AudioBuffer? _recordedVoice;
  web.AudioBufferSourceNode? _chimeSource;
  web.AudioBufferSourceNode? _voiceSource;
  // เก็บ reference ไว้ ไม่งั้น Chrome อาจเก็บขยะก่อนพูดจบแล้ว onend ไม่ถูกเรียก
  web.SpeechSynthesisUtterance? _utterance;
  Future<void>? _loading;

  web.AudioContext _audio() => _context ??= web.AudioContext();

  bool get _speechSupported => web.window.has('speechSynthesis');

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
    if (_speechSupported) {
      // iPhone ต้องเรียก speak ครั้งแรกจากการแตะจอ ครั้งต่อไปถึงพูดเองได้
      final synth = web.window.speechSynthesis;
      synth.getVoices(); // บางเบราว์เซอร์เริ่มโหลดรายชื่อเสียงตอนเรียกครั้งแรก
      synth.speak(web.SpeechSynthesisUtterance(' ')..volume = 0);
    }
    _loading ??= _load();
  }

  Future<void> _load() async {
    _chime = await _decode('assets/sounds/offer_alarm.wav');
    if (await hasOfferVoiceAsset()) {
      try {
        _recordedVoice = await _decode(offerVoiceAsset);
      } catch (_) {}
    }
  }

  Future<web.AudioBuffer> _decode(String asset) async {
    final data = await rootBundle.load(asset);
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return _audio().decodeAudioData(bytes.buffer.toJS).toDart;
  }

  web.AudioBufferSourceNode _play(web.AudioBuffer buffer) {
    final context = _audio();
    final source = context.createBufferSource()..buffer = buffer;
    source.connect(context.destination);
    source.start();
    return source;
  }

  @override
  Future<void> playChime() async {
    await (_loading ??= _load());
    final buffer = _chime;
    if (buffer == null) return;
    await _audio().resume().toDart;
    _chimeSource?.stop();
    _chimeSource = _play(buffer);
  }

  @override
  Future<void> speak(String text) async {
    await (_loading ??= _load());
    final recorded = _recordedVoice;
    if (recorded != null) {
      final done = Completer<void>();
      _voiceSource?.stop();
      _voiceSource = _play(recorded)
        ..onended = ((web.Event _) {
          if (!done.isCompleted) done.complete();
        }).toJS;
      return done.future;
    }
    final voice = _thaiVoice();
    // เครื่องไม่มีเสียงภาษาไทย: เล่นแค่เสียงปลุก ไม่ให้เสียงภาษาอื่นอ่านข้อความไทย
    if (voice == null) return;
    final synth = web.window.speechSynthesis;
    final done = Completer<void>();
    void finish(web.Event _) {
      if (!done.isCompleted) done.complete();
    }

    final utterance = web.SpeechSynthesisUtterance(text)
      ..lang = offerVoiceLanguage
      ..voice = voice
      ..rate = 1
      ..volume = 1
      ..onend = finish.toJS
      ..onerror = finish.toJS;
    _utterance = utterance;
    // Safari บางรุ่นทิ้งคำสั่ง speak ที่ตามหลัง cancel ทันที จึง cancel เฉพาะตอนพูดค้างอยู่
    if (synth.speaking || synth.pending) synth.cancel();
    synth.speak(utterance);
    return done.future;
  }

  web.SpeechSynthesisVoice? _thaiVoice() {
    if (!_speechSupported) return null;
    final voices = web.window.speechSynthesis.getVoices().toDart;
    final prefix = offerVoiceLanguage.split('-').first.toLowerCase();
    for (final voice in voices) {
      if (voice.lang.toLowerCase().replaceAll('_', '-').startsWith(prefix)) {
        return voice;
      }
    }
    return null;
  }

  @override
  Future<void> stopSound() async {
    _chimeSource?.stop();
    _chimeSource = null;
    _voiceSource?.stop();
    _voiceSource = null;
    if (_utterance != null && _speechSupported) {
      _utterance = null;
      web.window.speechSynthesis.cancel();
    }
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
