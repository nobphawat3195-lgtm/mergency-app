import 'dart:async';

import 'native_offer_alerts.dart';

NativeOfferAlerts createNativeOfferAlerts() => NoNativeOfferAlerts();

/// เว็บ (และเทสต์): ไม่มีแจ้งเตือนของระบบแบบแอป
class NoNativeOfferAlerts implements NativeOfferAlerts {
  @override
  Future<void> init() async {}
  @override
  Stream<OfferAlertAction> get actions => const Stream.empty();
  @override
  OfferAlertAction? takeLaunchAction() => null;
  @override
  Future<void> cancel(String orderId) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showTest() async {}
  @override
  Future<AlarmReadiness> readiness() async => const AlarmReadiness();
  @override
  Future<void> openSetting(AlarmSetting setting) async {}
}
