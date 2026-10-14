import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:fixgo_provider/offer_alarm.dart';
import 'package:fixgo_provider/screens/offer_alarm_overlay.dart';
import 'package:fixgo_provider/screens/offers_screen.dart';
import 'package:fixgo_provider/screens/web_alert_card.dart';
import 'package:fixgo_provider/web_alerts.dart';
import 'package:fixgo_provider/working_hours.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend implements OfferAlarmBackend {
  int chimes = 0;
  int stops = 0;

  @override
  bool get isInBackground => false;
  @override
  void unlock() {}
  @override
  void requestNotificationPermission() {}
  @override
  Future<void> playChime() async => chimes++;
  @override
  Future<void> speak(String text) async {}
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

  /// จำลองเซิร์ฟเวอร์ล่ม
  bool down = false;

  /// ลิงก์เพิ่มเพื่อน LINE OA ที่ backend ส่งมาในโปรไฟล์
  String? lineAddFriendUrl;

  @override
  Future<Map<String, dynamic>> getProviderProfile() async => {
        'status': 'VERIFIED',
        // ไม่เปิดตำแหน่ง GPS ในเทสต์ (ไม่มี plugin) สถานะออนไลน์ตั้งจากเทสต์เอง
        'isOnline': false,
        'openMinute': openMinute,
        'closeMinute': closeMinute,
        'lineAddFriendUrl': lineAddFriendUrl,
      };
  @override
  Future<WalletDebt> getWalletDebt() async =>
      const WalletDebt(balance: 0, owed: 0, limit: 0, blocked: false);
  @override
  Future<List<JobOffer>> listOffers() async {
    if (down) throw ApiException(503, 'Service Unavailable');
    return offers;
  }

  @override
  Future<List<Order>> listAssignedOrders() async => [];
  @override
  Future<List<WalletEntry>> listWalletEntries() async => [];
  @override
  Future<int> getWalletBalance() async => 0;
  @override
  Future<void> sendProviderHeartbeat() async {}
  final accepted = <String>[];
  final webPushRegistered = <String>[];

  @override
  Future<({bool enabled, String? publicKey})> getWebPushConfig() async =>
      (enabled: true, publicKey: 'BPublicKey');

  @override
  Future<void> registerWebPush({
    required String endpoint,
    required String p256dh,
    required String auth,
  }) async =>
      webPushRegistered.add(endpoint);

  @override
  Future<void> acceptOffer(String orderId) async {
    accepted.add(orderId);
    offers = [];
  }

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

class _FakeBrowser implements WebAlertPlatform {
  _FakeBrowser({
    required this.standalone,
    this.isIos = false,
    this.permission = 'default',
  });

  @override
  bool get isWeb => true;
  @override
  final bool standalone;
  @override
  final bool isIos;
  @override
  bool get pushSupported => true;
  @override
  String permission;
  final asked = <bool>[];

  @override
  Future<WebPushKeys?> subscribe(String publicKey, {required bool ask}) async {
    asked.add(ask);
    if (ask && permission == 'default') permission = 'granted';
    if (permission != 'granted') return null;
    return const WebPushKeys(
      endpoint: 'https://push.example/1',
      p256dh: 'p',
      auth: 'a',
    );
  }
}

JobOffer _offer(String id, {Duration left = const Duration(minutes: 2)}) =>
    JobOffer(
      orderId: id,
      orderNo: 'FG-$id',
      distanceKm: 2.4,
      expiresAt: DateTime.now().add(left),
      priceEstimated: 50000,
      subServiceName: 'จั๊มแบต',
    );

Future<(ProviderAppState, _Api, _Backend)> _pump(
  WidgetTester tester, {
  int open = allDayOpenMinute,
  int close = allDayCloseMinute,
  List<JobOffer> offers = const [],
  bool down = false,
  String? lineAddFriendUrl,
  WebAlertPlatform? webPlatform,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _Api(openMinute: open, closeMinute: close)
    ..offers = offers
    ..down = down
    ..lineAddFriendUrl = lineAddFriendUrl;
  final backend = _Backend();
  final state = ProviderAppState(
    api: api,
    offerAlarm: OfferAlarm(backend),
    webAlertPlatform: webPlatform,
  );
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

    expect(backend.chimes, 1);
    expect(find.byType(OfferAlarmOverlay), findsOneWidget);
    expect(find.text('งานใหม่!'), findsOneWidget);

    // ดังวนทุก 4 วิ (0, 4, 8) รอบดึงข้อมูลถัดไปเห็นงานเดิมไม่เริ่มปลุกซ้อน
    await tester.pump(const Duration(seconds: 10));
    expect(backend.chimes, 3);

    await tester.tap(find.text('ปิดเสียง'));
    await tester.pump();
    expect(backend.stops, 1);
    expect(find.byType(OfferAlarmOverlay), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    expect(backend.chimes, 3);

    // งานใหม่อีกงานปลุกอีกครั้ง
    api.offers = [_offer('1'), _offer('2')];
    await tester.pump(const Duration(seconds: 2));
    expect(backend.chimes, 4);
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

  testWidgets('a failed first load shows retry instead of empty or zero',
      (tester) async {
    final (_, api, _) = await _pump(tester, down: true);
    expect(find.text('โหลดงานที่กำลังทำไม่สำเร็จ'), findsOneWidget);
    expect(find.text('โหลดสรุปผลงานไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ยังไม่มีงานที่กำลังทำ'), findsNothing);
    expect(find.text('฿0'), findsNothing);
    expect(find.textContaining('Service'), findsNothing);

    api.down = false;
    await tester.tap(find.text('ลองใหม่').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ยังไม่มีงานที่กำลังทำ'), findsOneWidget);
    expect(find.text('โหลดสรุปผลงานไม่สำเร็จ'), findsNothing);
    expect(find.textContaining('ข้อมูลนี้อาจไม่ใช่ล่าสุด'), findsNothing);

    // โหลดได้แล้วรอบถัดไปล่ม: ตัวเลขเดิมยังอยู่ พร้อมแถบเตือน
    api.down = true;
    await tester.pump(const Duration(seconds: 11));
    expect(find.textContaining('ข้อมูลนี้อาจไม่ใช่ล่าสุด'), findsOneWidget);
    expect(find.text('งานเสร็จวันนี้'), findsOneWidget);
  });

  testWidgets('asks LINE mechanics to add the OA and can be hidden',
      (tester) async {
    await _pump(tester, lineAddFriendUrl: 'https://lin.ee/abc');
    const title = 'เพิ่มเพื่อน LINE FixGo เพื่อรับแจ้งเตือนงานใหม่';
    expect(find.text(title), findsOneWidget);
    expect(find.text('เพิ่มเพื่อน'), findsOneWidget);
    await tester.tap(find.text('เพิ่มแล้ว'));
    await tester.pump();
    expect(find.text(title), findsNothing);
  });

  testWidgets('no LINE card when the server sends no link', (tester) async {
    await _pump(tester);
    expect(
      find.text('เพิ่มเพื่อน LINE FixGo เพื่อรับแจ้งเตือนงานใหม่'),
      findsNothing,
    );
  });

  testWidgets('full-screen alarm shows the countdown and accepts the job',
      (tester) async {
    final (_, api, backend) = await _pump(tester, offers: [_offer('7')]);
    expect(find.byType(OfferAlarmOverlay), findsOneWidget);
    expect(find.textContaining('เหลือเวลา 1:5'), findsOneWidget);
    expect(find.textContaining('ราคาประเมิน ฿500'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(OfferAlarmOverlay),
        matching: find.text('รับงาน'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.accepted, ['7']);
    expect(find.byType(OfferAlarmOverlay), findsNothing);
    expect(backend.stops, greaterThan(0));
  });

  testWidgets('the alarm stops by itself when the offer expires',
      (tester) async {
    final (_, _, backend) = await _pump(
      tester,
      offers: [_offer('8', left: const Duration(seconds: 6))],
    );
    expect(find.byType(OfferAlarmOverlay), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(OfferAlarmOverlay), findsNothing);
    final chimes = backend.chimes;
    await tester.pump(const Duration(seconds: 12));
    expect(backend.chimes, chimes);
  });

  group('web alerts card', () {
    testWidgets('iPhone in a Safari tab is told how to add to Home Screen',
        (tester) async {
      await _pump(
        tester,
        webPlatform: _FakeBrowser(standalone: false, isIos: true),
      );
      expect(
        find.text('ติดตั้งแอปลงหน้าจอหลักเพื่อให้เตือนงานดังขึ้น'),
        findsOneWidget,
      );
      expect(find.textContaining('เพิ่มไปยังหน้าจอโฮม'), findsOneWidget);
      await tester.tap(find.text('ไว้ทีหลัง'));
      await tester.pump();
      expect(
        find.text('ติดตั้งแอปลงหน้าจอหลักเพื่อให้เตือนงานดังขึ้น'),
        findsNothing,
      );
    });

    testWidgets('installed app asks for notifications only from a tap',
        (tester) async {
      final browser = _FakeBrowser(standalone: true);
      final (_, api, _) = await _pump(tester, webPlatform: browser);
      // เปิดหน้าแล้วไม่ถามสิทธิ์เอง
      expect(browser.asked, isEmpty);
      expect(find.text('เปิดการแจ้งเตือนงานใหม่'), findsOneWidget);

      await tester.tap(find.text('เปิดการแจ้งเตือน'));
      await tester.pump();
      await tester.pump();
      expect(browser.asked, [true]);
      expect(api.webPushRegistered, ['https://push.example/1']);
      expect(find.text('เปิดการแจ้งเตือนงานใหม่'), findsNothing);
    });

    testWidgets('already allowed: re-registers quietly and shows no card',
        (tester) async {
      final browser = _FakeBrowser(standalone: true, permission: 'granted');
      final (_, api, _) = await _pump(tester, webPlatform: browser);
      expect(browser.asked, [false]);
      expect(api.webPushRegistered, ['https://push.example/1']);
      expect(find.byType(WebAlertCard), findsNothing);
    });

    testWidgets('blocked notifications explain where to turn them on',
        (tester) async {
      await _pump(
        tester,
        webPlatform: _FakeBrowser(
          standalone: true,
          isIos: true,
          permission: 'denied',
        ),
      );
      expect(find.text('การแจ้งเตือนถูกปิดอยู่'), findsOneWidget);
      expect(find.textContaining('การตั้งค่า > การแจ้งเตือน'), findsOneWidget);
    });

    testWidgets('the mobile app never shows the web card', (tester) async {
      await _pump(tester);
      expect(find.byType(WebAlertCard), findsNothing);
    });
  });
}
