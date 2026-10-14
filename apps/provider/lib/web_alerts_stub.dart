import 'web_alerts.dart';

WebAlertPlatform createWebAlertPlatform() => _NativePlatform();

/// แอปมือถือใช้ push ของระบบ (FCM/APNs) ไม่ใช้ Web Push
class _NativePlatform implements WebAlertPlatform {
  @override
  bool get isWeb => false;
  @override
  bool get standalone => true;
  @override
  bool get isIos => false;
  @override
  bool get pushSupported => false;
  @override
  String get permission => 'denied';
  @override
  Future<WebPushKeys?> subscribe(String publicKey, {required bool ask}) async =>
      null;
}
