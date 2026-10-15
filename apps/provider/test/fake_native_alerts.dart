import 'dart:async';

import 'package:fixgo_provider/native_offer_alerts.dart';

/// แจ้งเตือนของระบบปลอมสำหรับเทสต์ (บันทึกว่าแอปเรียกอะไร)
class FakeNativeAlerts implements NativeOfferAlerts {
  FakeNativeAlerts({
    this.status = const AlarmReadiness(),
    this.launch,
  });

  AlarmReadiness status;
  OfferAlertAction? launch;
  final controller = StreamController<OfferAlertAction>.broadcast();
  final calls = <String>[];

  @override
  Future<void> init() async => calls.add('init');
  @override
  Stream<OfferAlertAction> get actions => controller.stream;
  @override
  OfferAlertAction? takeLaunchAction() {
    final action = launch;
    launch = null;
    return action;
  }

  @override
  Future<void> cancel(String orderId) async => calls.add('cancel:$orderId');
  @override
  Future<void> cancelAll() async => calls.add('cancelAll');
  @override
  Future<void> showTest() async => calls.add('showTest');
  @override
  Future<AlarmReadiness> readiness() async => status;
  @override
  Future<void> openSetting(AlarmSetting setting) async =>
      calls.add('open:${setting.name}');
}
