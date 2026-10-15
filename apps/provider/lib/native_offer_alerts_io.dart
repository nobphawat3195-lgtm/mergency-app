import 'dart:async';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_state.dart';
import 'native_offer_alerts.dart';
import 'offer_alarm_channel.dart';

NativeOfferAlerts createNativeOfferAlerts() => _DeviceOfferAlerts();

const _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  // ขอสิทธิ์ตอนกดพร้อมรับงาน/หน้าตั้งค่า ไม่ใช่ตอนเปิดแอป
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  ),
);

/// ช่องทางคุยกับ MainActivity (Android) เรื่องสิทธิ์เต็มจอและการประหยัดแบต
const _settingsChannel = MethodChannel('fixgo/alarm_settings');

/// แสดงแจ้งเตือนงานใหม่แบบนาฬิกาปลุก (งานหมดเวลาแล้วไม่แสดง)
Future<void> showOfferAlarm(
  FlutterLocalNotificationsPlugin plugin, {
  required String orderId,
  required String title,
  required String body,
  required DateTime expiresAt,
}) async {
  final left = expiresAt.difference(DateTime.now());
  if (left <= Duration.zero) return;
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(offerAlarmChannel);
  await plugin.show(
    offerNotificationId(orderId),
    title,
    body,
    NotificationDetails(
      android: offerAlarmAndroidDetails(title: title, timeLeft: left),
      iOS: offerAlarmDarwinDetails(orderId),
    ),
    payload: orderId,
  );
}

/// push จาก FCM ตอนแอปอยู่เบื้องหลังหรือถูกปิด (Android, isolate แยก)
///
/// backend ส่งงานใหม่แบบ data อย่างเดียว แอปจึงแสดงแจ้งเตือนนาฬิกาปลุกเองได้แม้แอปถูกปิด
/// iOS ไม่ผ่านตรงนี้: APNs แสดงแจ้งเตือน Time Sensitive พร้อมเสียงให้เอง
@pragma('vm:entry-point')
Future<void> offerPushBackgroundHandler(RemoteMessage message) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final data = message.data;
  final type = data['type'];
  final orderId = data['orderId'];
  if (type is! String || orderId is! String || orderId.isEmpty) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    _initSettings,
    onDidReceiveBackgroundNotificationResponse:
        offerNotificationBackgroundResponse,
  );
  if (type == 'OFFER') {
    final expiresAt = DateTime.tryParse(data['expiresAt'] as String? ?? '');
    if (expiresAt == null) return;
    await showOfferAlarm(
      plugin,
      orderId: orderId,
      title: data['title'] as String? ?? 'มีงานใหม่ใกล้คุณ',
      body: data['body'] as String? ?? 'เปิดแอปเพื่อกดรับงานก่อนหมดเวลา',
      expiresAt: expiresAt,
    );
  } else if (type == 'OFFER_CANCELLED' || type == 'OFFER_EXPIRED') {
    await plugin.cancel(offerNotificationId(orderId));
  }
}

/// ปุ่ม "ปฏิเสธ" ตอนแอปปิดอยู่: ส่งปฏิเสธเองโดยไม่เปิดแอป (isolate แยก)
@pragma('vm:entry-point')
void offerNotificationBackgroundResponse(NotificationResponse response) {
  final orderId = response.payload;
  if (response.actionId != rejectActionId || orderId == null) return;
  unawaited(_rejectInBackground(orderId));
}

Future<void> _rejectInBackground(String orderId) async {
  DartPluginRegistrant.ensureInitialized();
  try {
    final token = await const SecureTokenStore(providerTokenStoreKey).read();
    if (token == null || token.isEmpty) return;
    final api = FixGoApiClient(baseUrl: AppConfig.apiBaseUrl)
      ..accessToken = token;
    await api.rejectOffer(orderId);
    api.dispose();
  } catch (_) {
    // ปฏิเสธไม่สำเร็จก็ไม่เป็นไร ข้อเสนอจะหมดเวลาแล้วส่งต่อช่างคนอื่นเอง
  }
}

class _DeviceOfferAlerts implements NativeOfferAlerts {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _actions = StreamController<OfferAlertAction>.broadcast();
  OfferAlertAction? _launchAction;
  bool _ready = false;

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Stream<OfferAlertAction> get actions => _actions.stream;

  @override
  OfferAlertAction? takeLaunchAction() {
    final action = _launchAction;
    _launchAction = null;
    return action;
  }

  static OfferAlertAction? _toAction(NotificationResponse response) {
    final orderId = response.payload;
    if (orderId == null || orderId.isEmpty) return null;
    return OfferAlertAction(
      orderId: orderId,
      kind: switch (response.actionId) {
        acceptActionId => OfferAlertActionKind.accept,
        rejectActionId => OfferAlertActionKind.reject,
        _ => OfferAlertActionKind.open,
      },
    );
  }

  /// ห้าม throw: แจ้งเตือนเริ่มไม่ได้ต้องไม่ทำให้แอปเปิดไม่ขึ้น
  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        _initSettings,
        onDidReceiveNotificationResponse: (response) {
          final action = _toAction(response);
          if (action != null) _actions.add(action);
        },
        onDidReceiveBackgroundNotificationResponse:
            offerNotificationBackgroundResponse,
      );
      await _androidPlugin?.createNotificationChannel(offerAlarmChannel);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _launchAction = _toAction(response);
      }
      if (PushNotifications.instance.isEnabled && _android) {
        FirebaseMessaging.onBackgroundMessage(offerPushBackgroundHandler);
        // แอปเปิดอยู่แล้วงานถูกรับไป/หมดเวลา: ลบแจ้งเตือนที่อาจค้างจากตอนอยู่เบื้องหลัง
        PushNotifications.instance.onReceived.listen((event) {
          if (event.type == 'OFFER_CANCELLED' ||
              event.type == 'OFFER_EXPIRED') {
            unawaited(cancel(event.orderId));
          }
        });
      }
      _ready = true;
    } catch (error, stackTrace) {
      reportError(error, stackTrace);
    }
  }

  @override
  Future<void> cancel(String orderId) async {
    try {
      await _plugin.cancel(offerNotificationId(orderId));
    } catch (_) {}
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready || !_android) return;
    try {
      final active = await _androidPlugin?.getActiveNotifications() ?? [];
      for (final notification in active) {
        if (notification.channelId == offerAlarmChannel.id &&
            notification.id != null) {
          await _plugin.cancel(notification.id!);
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> showTest() async {
    await init();
    await _androidPlugin?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
    // ให้เวลาช่างกดล็อกจอก่อน แล้วค่อยเด้งเหมือนงานจริง (หายเองใน 30 วิ)
    await Future<void>.delayed(const Duration(seconds: 5));
    await showOfferAlarm(
      _plugin,
      orderId: 'test-alarm',
      title: 'ทดสอบ: มีงานใหม่ใกล้คุณ',
      body: 'นี่คือเสียงและหน้าจอเมื่อมีงานจริง แตะเพื่อปิด',
      expiresAt: DateTime.now().add(const Duration(seconds: 30)),
    );
  }

  Future<bool?> _ask(String method) async {
    if (!_android) return null;
    try {
      return await _settingsChannel.invokeMethod<bool>(method);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AlarmReadiness> readiness() async {
    if (!_android) return const AlarmReadiness();
    await init();
    bool? notifications;
    try {
      notifications = await _androidPlugin?.areNotificationsEnabled();
    } catch (_) {}
    return AlarmReadiness(
      notifications: notifications,
      fullScreen: await _ask('canUseFullScreenIntent'),
      batteryUnrestricted: await _ask('isIgnoringBatteryOptimizations'),
    );
  }

  @override
  Future<void> openSetting(AlarmSetting setting) async {
    if (!_android) return;
    switch (setting) {
      case AlarmSetting.notifications:
        // ยังไม่เคยถาม: ถามในแอปก่อน ถ้าเคยปฏิเสธแล้วระบบจะไม่ถามซ้ำ จึงเปิดหน้าตั้งค่าแทน
        final granted = await _androidPlugin?.requestNotificationsPermission();
        if (granted != true) await _ask('openNotificationSettings');
      case AlarmSetting.fullScreen:
        await _ask('openFullScreenIntentSettings');
      case AlarmSetting.battery:
        await _ask('openBatteryOptimizationSettings');
      case AlarmSetting.appDetails:
        await _ask('openAppSettings');
    }
  }
}
