import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  FlutterLocalNotificationsPlugin? _notifications;
  Future<void>? _ready;

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

  @override
  Future<void> startSound() async {
    final player = _player ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    // ดังแม้เปิดโหมดเงียบ (iOS) เหมือนนาฬิกาปลุก
    await player.play(
      AssetSource('sounds/offer_alarm.wav'),
      volume: 1,
      ctx: AudioContextConfig(respectSilence: false).build(),
    );
  }

  @override
  Future<void> stopSound() async {
    await _player?.stop();
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
