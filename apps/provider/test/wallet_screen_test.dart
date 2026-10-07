import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:fixgo_provider/offer_alarm.dart';
import 'package:fixgo_provider/screens/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend implements OfferAlarmBackend {
  @override
  bool get isInBackground => false;
  @override
  void unlock() {}
  @override
  void requestNotificationPermission() {}
  @override
  Future<void> playChime() async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stopSound() async {}
  @override
  void vibrate() {}
  @override
  Future<void> notify(String title, String body) async {}
}

class _Api extends FixGoApiClient {
  _Api() : super(baseUrl: 'https://api.example.com');

  bool fail = true;

  @override
  Future<int> getWalletBalance() async {
    if (fail) throw ApiException(500, 'Internal server error');
    return 125000;
  }

  @override
  Future<List<WalletEntry>> listWalletEntries() async => const [];

  @override
  Future<WalletDebt> getWalletDebt() async =>
      const WalletDebt(balance: 0, owed: 0, limit: 0, blocked: false);
}

void main() {
  testWidgets('a failed load never shows a ฿0 balance and can retry',
      (tester) async {
    final api = _Api();
    final state =
        ProviderAppState(api: api, offerAlarm: OfferAlarm(_Backend()));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderAppScope(
        state: state,
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('โหลดกระเป๋าเงินไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง'), findsOneWidget);
    expect(find.text('฿0'), findsNothing);
    expect(find.textContaining('Internal'), findsNothing);

    api.fail = false;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pump();
    await tester.pump();
    expect(find.text('฿1,250'), findsOneWidget);
    expect(
      find.text('ยังไม่มีรายการ รายได้จากงานที่ปิดแล้วจะแสดงที่นี่'),
      findsOneWidget,
    );
  });
}
