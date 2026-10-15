import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:fixgo_provider/native_offer_alerts.dart';
import 'package:fixgo_provider/screens/alarm_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_native_alerts.dart';

Future<FakeNativeAlerts> _pump(
    WidgetTester tester, AlarmReadiness status) async {
  final alerts = FakeNativeAlerts(status: status);
  final state = ProviderAppState(
    api: FixGoApiClient(baseUrl: 'https://api.example.com'),
    nativeAlerts: alerts,
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ProviderAppScope(
      state: state,
      child: const MaterialApp(home: AlarmSettingsScreen()),
    ),
  );
  await tester.pump();
  return alerts;
}

void main() {
  testWidgets('Android checklist shows what is missing and opens the setting',
      (tester) async {
    final alerts = await _pump(
      tester,
      const AlarmReadiness(
        notifications: true,
        fullScreen: false,
        batteryUnrestricted: false,
      ),
    );
    expect(find.text('อนุญาตการแจ้งเตือน'), findsOneWidget);
    expect(find.text('แสดงเต็มจอตอนล็อกจอ'), findsOneWidget);
    expect(find.text('ไม่จำกัดแบตเตอรี่ให้แอปนี้'), findsOneWidget);
    expect(find.text('เรียบร้อย'), findsOneWidget);

    await tester.tap(find.text('ตั้งค่า').first);
    await tester.pump();
    expect(alerts.calls, contains('open:fullScreen'));

    await tester.tap(find.text('ทดสอบตอนล็อกจอ (เด้งใน 5 วินาที)'));
    await tester.pump();
    expect(alerts.calls, contains('showTest'));
  });

  testWidgets('iPhone only gets the sound test', (tester) async {
    await _pump(tester, const AlarmReadiness());
    expect(find.text('อนุญาตการแจ้งเตือน'), findsNothing);
    expect(find.text('ทดสอบเสียงเตือนงาน'), findsOneWidget);
    expect(find.text('ทดสอบตอนล็อกจอ (เด้งใน 5 วินาที)'), findsNothing);
  });
}
