import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// ค่า Firebase ต่อแอป ส่งตอน build ด้วย --dart-define (ไม่เก็บไฟล์ config ไว้ใน repo)
///
/// ```
/// flutter build ipa \
///   --dart-define=FIREBASE_PROJECT_ID=fixgo-prod \
///   --dart-define=FIREBASE_SENDER_ID=1234567890 \
///   --dart-define=FIREBASE_API_KEY=AIza... \
///   --dart-define=FIREBASE_IOS_APP_ID=1:1234567890:ios:abc \
///   --dart-define=FIREBASE_ANDROID_APP_ID=1:1234567890:android:def
/// ```
/// ไม่ตั้งค่า = ปิด push ทั้งหมด แอปยังทำงานปกติด้วยการดึงสถานะจาก API
abstract final class PushConfig {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');

  static FirebaseOptions? get options {
    if (kIsWeb) return null;
    final String appId;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        appId = iosAppId;
      case TargetPlatform.android:
        appId = androidAppId;
      default:
        return null;
    }
    if (projectId.isEmpty || senderId.isEmpty || apiKey.isEmpty) return null;
    if (appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }
}

/// ข้อความ push ที่แอปสนใจ: ประเภทเหตุการณ์ + ออเดอร์ที่เกี่ยวข้อง
@immutable
class PushEvent {
  const PushEvent({
    required this.type,
    required this.orderId,
    this.title,
    this.body,
  });

  /// OFFER, MATCHED, EN_ROUTE, IN_PROGRESS, QUOTE_PROPOSED, QUOTE_APPROVED,
  /// QUOTE_REJECTED, COMPLETED, CANCELLED, PAID, NO_MATCH
  final String type;
  final String orderId;
  final String? title;
  final String? body;

  static PushEvent? fromMessage(RemoteMessage message) {
    final type = message.data['type'];
    final orderId = message.data['orderId'];
    if (type is! String || orderId is! String) return null;
    return PushEvent(
      type: type,
      orderId: orderId,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }
}

/// แจ้งเตือนผ่าน Firebase Cloud Messaging
///
/// - [init] เรียกครั้งเดียวตอนเปิดแอป
/// - [attach] หลังล็อกอิน: ขอสิทธิ์แจ้งเตือนแล้วส่งโทเคนให้ backend
/// - [detach] ก่อนล็อกเอาต์: ถอนโทเคน เครื่องนี้จะไม่ได้รับแจ้งเตือนของบัญชีเดิมอีก
///
/// push เป็นแค่สัญญาณให้ไปดึงข้อมูลใหม่ สถานะจริงมาจาก API เสมอ
class PushNotifications {
  PushNotifications._();

  static final PushNotifications instance = PushNotifications._();

  bool _enabled = false;
  String? _registeredToken;
  StreamSubscription<String>? _tokenRefresh;
  PushEvent? _launchEvent;

  final _opened = StreamController<PushEvent>.broadcast();
  final _received = StreamController<PushEvent>.broadcast();
  final _any = StreamController<PushEvent>.broadcast();

  bool get isEnabled => _enabled;

  /// ผู้ใช้แตะแจ้งเตือนตอนแอปอยู่เบื้องหลัง
  Stream<PushEvent> get onOpened => _opened.stream;

  /// ได้รับแจ้งเตือนตอนเปิดแอปอยู่ (ระบบไม่แสดงแบนเนอร์บน Android ให้แอปแสดงเอง)
  Stream<PushEvent> get onReceived => _received.stream;

  /// ทั้งสองแบบข้างบน ใช้สั่งให้หน้าจอดึงข้อมูลใหม่ทันที
  Stream<PushEvent> get onAny => _any.stream;

  /// แจ้งเตือนที่ผู้ใช้แตะจนแอปเปิดขึ้นจากสถานะปิด อ่านได้ครั้งเดียว
  PushEvent? takeLaunchEvent() {
    final event = _launchEvent;
    _launchEvent = null;
    return event;
  }

  /// ห้าม throw: Firebase เริ่มไม่ได้ต้องไม่ทำให้แอปเปิดไม่ขึ้น
  Future<void> init() async {
    final options = PushConfig.options;
    if (options == null || _enabled) return;
    try {
      await Firebase.initializeApp(options: options);
      final messaging = FirebaseMessaging.instance;
      // iOS: แสดงแบนเนอร์และเสียงแม้แอปเปิดอยู่ ลูกค้า/ช่างต้องไม่พลาดสถานะงาน
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen((message) {
        final event = PushEvent.fromMessage(message);
        if (event == null) return;
        _received.add(event);
        _any.add(event);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final event = PushEvent.fromMessage(message);
        if (event == null) return;
        _opened.add(event);
        _any.add(event);
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null) _launchEvent = PushEvent.fromMessage(initial);
      _enabled = true;
    } catch (error) {
      debugPrint('ปิด push: เริ่ม Firebase ไม่สำเร็จ ($error)');
    }
  }

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';

  Future<void> attach(FixGoApiClient api) async {
    if (!_enabled) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token == null) return;
      await api.registerDevice(token, _platform);
      _registeredToken = token;

      await _tokenRefresh?.cancel();
      _tokenRefresh = messaging.onTokenRefresh.listen((fresh) async {
        if (api.accessToken == null) return;
        try {
          await api.registerDevice(fresh, _platform);
          _registeredToken = fresh;
        } catch (_) {
          // ครั้งหน้าที่เปิดแอป attach จะลงทะเบียนใหม่อีกครั้ง
        }
      });
    } catch (error) {
      debugPrint('ลงทะเบียน push ไม่สำเร็จ: $error');
    }
  }

  /// เรียกก่อนล้าง accessToken: คำขอถอนโทเคนต้องใช้ token ของบัญชีเดิม
  Future<void> detach(FixGoApiClient api) async {
    final token = _registeredToken;
    _registeredToken = null;
    final pending = _tokenRefresh?.cancel();
    _tokenRefresh = null;
    if (token == null) return;
    // เริ่มคำขอทันทีก่อน await ใดๆ ส่วนหัว Authorization จึงยังเป็นของบัญชีเดิม
    final unregister = api.unregisterDevice(token);
    try {
      await pending;
      await unregister;
    } catch (_) {
      // backend จะลบโทเคนเองเมื่อ FCM แจ้งว่าใช้ไม่ได้ หรือเมื่อมีบัญชีอื่นลงทะเบียนทับ
    }
  }
}
