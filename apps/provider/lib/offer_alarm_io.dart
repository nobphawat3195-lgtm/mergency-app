import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'offer_alarm.dart';

OfferAlarmBackend createOfferAlarmBackend() => _NativeOfferAlarm();

/// ช่องแจ้งเตือนเสียงดังสำหรับงานใหม่ (Android ตั้งความสำคัญสูงสุด แสดงทับจอ)
const _channel = AndroidNotificationChannel(
  'fixgo_offer_alarm',
  'งานใหม่',
  description: 'แจ้งเตือนเมื่อมีงานใหม่ใกล้คุณ',
  importance: Importance.max,
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

class _NativeOfferAlarm implements OfferAlarmBackend {
  // สร้างตอนใช้ครั้งแรก: เทสต์ที่ไม่มี plugin จะไม่แตะ platform channel
  AudioPlayer? _player;
  AudioPlayer? _voicePlayer;
  FlutterTts? _tts;
  FlutterLocalNotificationsPlugin? _notifications;
  Future<void>? _ready;
  Future<_Voice>? _voice;

  @override
  bool get isInBackground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state != null && state != AppLifecycleState.resumed;
  }

  // แอปมือถือเล่นเสียงได้เลย ไม่ต้องปลดล็อก
  @override
  void unlock() {}

  Future<FlutterLocalNotificationsPlugin> _plugin() async {
    final plugin = _notifications ??= FlutterLocalNotificationsPlugin();
    await (_ready ??= () async {
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // ขออนุญาตตอนกดพร้อมรับงาน ไม่ใช่ตอนเปิดแอป
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }());
    return plugin;
  }

  @override
  void requestNotificationPermission() {
    unawaited(() async {
      try {
        final plugin = await _plugin();
        await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        await plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true);
      } catch (_) {}
    }());
  }

  // ดังแม้เปิดโหมดเงียบ (iOS) เหมือนนาฬิกาปลุก
  static final _loud = AudioContextConfig(respectSilence: false).build();

  @override
  Future<void> playChime() async {
    final player = _player ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.play(
      AssetSource('sounds/offer_alarm.wav'),
      volume: 1,
      ctx: _loud,
    );
  }

  /// เลือกครั้งเดียว: ไฟล์เสียงที่อัดเอง > TTS ภาษาไทย > ไม่พูด
  Future<_Voice> _pickVoice() async {
    if (await hasOfferVoiceAsset()) return _Voice.recorded;
    final tts = _tts ??= FlutterTts();
    try {
      if (await tts.isLanguageAvailable(offerVoiceLanguage) != true) {
        return _Voice.none;
      }
      await tts.setLanguage(offerVoiceLanguage);
      // flutter_tts ใช้ 0.5 เป็นความเร็วปกติทั้ง Android และ iOS
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1);
      await tts.awaitSpeakCompletion(true);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await tts.setSharedInstance(true);
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
        );
      }
      return _Voice.tts;
    } catch (_) {
      return _Voice.none;
    }
  }

  @override
  Future<void> speak(String text) async {
    switch (await (_voice ??= _pickVoice())) {
      case _Voice.recorded:
        final player = _voicePlayer ??= AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        final done = player.onPlayerComplete.first;
        await player.play(
          AssetSource(offerVoiceAsset.replaceFirst('assets/', '')),
          volume: 1,
          ctx: _loud,
        );
        await done;
      case _Voice.tts:
        await _tts?.speak(text);
      case _Voice.none:
        return;
    }
  }

  @override
  Future<void> stopSound() async {
    await _player?.stop();
    await _voicePlayer?.stop();
    await _tts?.stop();
  }

  @override
  void vibrate() {
    unawaited(HapticFeedback.vibrate());
  }

  /// แจ้งเตือนในเครื่องตอนแอปยังทำงานอยู่เบื้องหลัง
  /// (แอปถูกปิดสนิทต้องใช้ push จาก Firebase ซึ่งยังไม่ได้ตั้งค่า)
  @override
  Future<void> notify(String title, String body) async {
    final plugin = await _plugin();
    await plugin.show(
      7001,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          ticker: title,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }
}

enum _Voice { recorded, tts, none }
