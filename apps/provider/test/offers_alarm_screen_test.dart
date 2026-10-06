import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:fixgo_provider/offer_alarm.dart';
import 'package:fixgo_provider/screens/offers_screen.dart';
import 'package:fixgo_provider/working_hours.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend implements OfferAlarmBackend {
  int starts = 0;
  int stops = 0;

  @override
  bool get isInBackground => false;
  @override
  void unlock() {}
  @override
  void requestNotificationPermission() {}
  @override
  Future<void> startSound() async => starts++;
  @override
  Future<void> stopSound() async => stops++;
  @override
  void vibrate() {}
  @override
  Future<void> notify(String title, String body) async {}
}

class _Api extends FixGoApiClient {
  _Api({required this.openMinute, required this.closeMinute})
      : super(baseUrl: 'https://api.example.com');

  int openMinute;
  int closeMinute;
  List<JobOffer> offers = [];
  final rejected = <String>[];

  @override
  Future<Map<String, dynamic>> getProviderProfile() async => {
        'status': 'VERIFIED',
        // ไม่เปิดตำแหน่ง GPS ในเทสต์ (ไม่มี plugin) สถานะออนไลน์ตั้งจากเทสต์เอง
        'isOnline': false,
        'openMinute': openMinute,
        'closeMinute': closeMinute,
      };
  @override
  Future<WalletDebt> getWalletDebt() async =>
      const WalletDebt(balance: 0, owed: 0, limit: 0, blocked: false);
  @override
  Future<List<JobOffer>> listOffers() async => offers;
  @override
  Future<List<Order>> listAssignedOrders() async => [];
  @override
  Future<List<WalletEntry>> listWalletEntries() async => [];
  @override
  Future<int> getWalletBalance() async => 0;
  @override
  Future<void> sendProviderHeartbeat() async {}
  @override
  Future<void> rejectOffer(String orderId) async {
    rejected.add(orderId);
    offers = [];
  }

  @override
  Future<({int openMinute, int closeMinute})> updateProviderHours({
    required int openMinute,
    required int closeMinute,
  }) async {
    this.openMinute = openMinute;
    this.closeMinute = closeMinute;
    return (openMinute: openMinute, closeMinute: closeMinute);
  }
}

JobOffer _offer(String id) => JobOffer(
      orderId: id,
      orderNo: 'FG-$id',
      distanceKm: 2.4,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      priceEstimated: 50000,
      subServiceName: 'จั๊มแบต',
    );

Future<(ProviderAppState, _Api, _Backend)> _pump(
  WidgetTester tester, {
  int open = allDayOpenMinute,
  int close = allDayCloseMinute,
  List<JobOffer> offers = const [],
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _Api(openMinute: open, closeMinute: close)..offers = offers;
  final backend = _Backend();
  final state = ProviderAppState(api: api, offerAlarm: OfferAlarm(backend));
  await tester.pumpWidget(
    ProviderAppScope(
      state: state,
      child: const MaterialApp(home: OffersScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  addTearDown(() async {
    // ปิดหน้าก่อน dispose state เพื่อหยุด timer ของหน้าหลัก
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  return (state, api, backend);
}

void main() {
  testWidgets('new offer rings and flashes until the mechanic answers',
      (tester) async {
    final (_, api, backend) = await _pump(tester, offers: [_offer('1')]);

    expect(backend.starts, 1);
    expect(find.text('งานใหม่! กดรับหรือปฏิเสธก่อนหมดเวลา'), findsOneWidget);

    // รอบดึงข้อมูลถัดไปเห็นงานเดิม ไม่ปลุกซ้ำ
    await tester.pump(const Duration(seconds: 10));
    expect(backend.starts, 1);

    await tester.tap(find.text('ปิดเสียง'));
    await tester.pump();
    expect(backend.stops, 1);
    expect(find.text('งานใหม่! กดรับหรือปฏิเสธก่อนหมดเวลา'), findsNothing);

    // งานใหม่อีกงานปลุกอีกครั้ง
    api.offers = [_offer('1'), _offer('2')];
    await tester.pump(const Duration(seconds: 10));
    expect(backend.starts, 2);
  });

  testWidgets('shows the current job hours under the switch', (tester) async {
    await _pump(tester, open: 8 * 60, close: 20 * 60);
    expect(find.text('รับงาน: 08:00-20:00'), findsOneWidget);
  });

  testWidgets('online outside job hours warns and can switch to all day',
      (tester) async {
    // ช่วง 1 นาทีที่ห่างจากตอนนี้ 12 ชม. = นอกเวลาแน่นอน
    final away = (bangkokMinuteOfDay() + 720) % 1440;
    final (state, api, _) = await _pump(tester, open: away, close: away);
    expect(find.textContaining('นอกเวลารับงาน'), findsNothing);

    state.setOnline(true);
    await tester.pump();
    expect(
      find.text('ตอนนี้นอกเวลารับงานที่ตั้งไว้ ระบบจะไม่ส่งงานให้'),
      findsOneWidget,
    );

    await tester.tap(find.text('รับงานตอนนี้เลย (ตลอดเวลา)'));
    await tester.pump();
    expect((api.openMinute, api.closeMinute), (0, 1439));
    expect(
      find.text('ตอนนี้นอกเวลารับงานที่ตั้งไว้ ระบบจะไม่ส่งงานให้'),
      findsNothing,
    );
    expect(find.text('รับงาน: ตลอดเวลา'), findsOneWidget);
    state.setOnline(false);
  });
}
