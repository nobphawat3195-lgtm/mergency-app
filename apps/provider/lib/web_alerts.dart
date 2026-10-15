import 'package:fixgo_core/fixgo_core.dart';

import 'web_alerts_stub.dart' if (dart.library.js_interop) 'web_alerts_web.dart'
    as platform;

/// subscription ของเบราว์เซอร์นี้ (ส่งให้ backend ใช้ส่ง Web Push)
class WebPushKeys {
  const WebPushKeys({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
}

/// ความสามารถของเบราว์เซอร์ที่เปิดเว็บแอปช่างอยู่ (แอปมือถือ: ไม่รองรับทั้งหมด)
abstract class WebAlertPlatform {
  /// เปิดผ่านเว็บ (ไม่ใช่แอปจากสโตร์)
  bool get isWeb;

  /// เปิดจากไอคอนบนหน้าจอหลัก (ติดตั้งแล้ว) ไม่ใช่แท็บเบราว์เซอร์
  bool get standalone;

  /// iPhone/iPad: ต้องติดตั้งลงหน้าจอหลักก่อนถึงจะรับ Web Push ได้ (iOS 16.4+)
  bool get isIos;

  /// เบราว์เซอร์มี Service Worker + Push + Notification
  bool get pushSupported;

  /// default / granted / denied
  String get permission;

  /// สมัคร push ด้วย VAPID public key ถ้า [ask] = true จะถามสิทธิ์แจ้งเตือนก่อน
  /// (ต้องเรียกจากการแตะจอเท่านั้น) คืน null เมื่อไม่ได้รับอนุญาตหรือสมัครไม่สำเร็จ
  Future<WebPushKeys?> subscribe(String publicKey, {required bool ask});
}

WebAlertPlatform createWebAlertPlatform() => platform.createWebAlertPlatform();

/// สิ่งที่การ์ด "แจ้งเตือนงานใหม่" ในหน้าหลักต้องบอกช่าง
enum WebAlertStatus {
  /// ไม่ต้องแสดงการ์ด (แอปมือถือ หรือพร้อมรับแจ้งเตือนแล้ว)
  ready,

  /// เปิดในแท็บเบราว์เซอร์: ชวนติดตั้งลงหน้าจอหลัก (iPhone ยังรับ push ไม่ได้จนกว่าจะติดตั้ง)
  install,

  /// ติดตั้งแล้ว/รองรับ push แต่ยังไม่ได้อนุญาต: ปุ่ม "เปิดการแจ้งเตือน"
  askPermission,

  /// ช่างกดไม่อนุญาตไว้: บอกวิธีเปิดในตั้งค่า
  blocked,
}

/// ประสาน Web Push ระหว่างเบราว์เซอร์กับ backend
///
/// ไม่ throw: แจ้งเตือนเป็นช่องทางเสริม เปิดไม่ได้ช่างยังรับงานจากหน้าจอได้ตามปกติ
class WebAlerts {
  WebAlerts(this.platform);

  final WebAlertPlatform platform;
  String? _publicKey;
  bool _serverEnabled = false;

  /// endpoint ที่ผูกกับบัญชีอยู่ ใช้ถอนตอนล็อกเอาต์
  String? _registeredEndpoint;

  bool get _canPush =>
      platform.pushSupported && _serverEnabled && _publicKey != null;

  /// ถามสิทธิ์แจ้งเตือนได้เลย (ใช้คู่กับการ์ดติดตั้ง บน Android ที่ยังเปิดในแท็บ)
  bool get canAskPermission => _canPush && platform.permission == 'default';

  /// สถานะสำหรับการ์ดในหน้าหลัก
  WebAlertStatus get status {
    if (!platform.isWeb) return WebAlertStatus.ready;
    final pushReady = _canPush && platform.permission == 'granted';
    if (!platform.standalone && !pushReady) return WebAlertStatus.install;
    if (!_canPush) return WebAlertStatus.ready;
    return switch (platform.permission) {
      'granted' => WebAlertStatus.ready,
      'denied' => WebAlertStatus.blocked,
      _ => WebAlertStatus.askPermission,
    };
  }

  /// เรียกตอนเปิดหน้าหลัก: อ่านการตั้งค่า ถ้าเคยอนุญาตแล้วผูก subscription ให้ใหม่เงียบๆ
  Future<void> refresh(FixGoApiClient api) async {
    if (!platform.isWeb || !platform.pushSupported) return;
    try {
      final config = await api.getWebPushConfig();
      _serverEnabled = config.enabled;
      _publicKey = config.publicKey;
      if (_canPush && platform.permission == 'granted') {
        await _register(api, ask: false);
      }
    } catch (_) {}
  }

  /// ช่างแตะ "เปิดการแจ้งเตือน" คืน true เมื่อพร้อมรับแจ้งเตือนแล้ว
  Future<bool> enable(FixGoApiClient api) async {
    if (!_canPush) return false;
    try {
      return await _register(api, ask: true);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _register(FixGoApiClient api, {required bool ask}) async {
    final keys = await platform.subscribe(_publicKey!, ask: ask);
    if (keys == null) return false;
    await api.registerWebPush(
      endpoint: keys.endpoint,
      p256dh: keys.p256dh,
      auth: keys.auth,
    );
    _registeredEndpoint = keys.endpoint;
    return true;
  }

  /// เรียกก่อนล้าง accessToken: คำขอเริ่มทันทีจึงยังใช้ส่วนหัวของบัญชีเดิม
  Future<void> detach(FixGoApiClient api) async {
    final endpoint = _registeredEndpoint;
    _registeredEndpoint = null;
    if (endpoint == null) return;
    try {
      await api.unregisterWebPush(endpoint);
    } catch (_) {
      // บัญชีใหม่ที่ล็อกอินบนเครื่องนี้จะผูก endpoint เดิมทับเอง
    }
  }
}
