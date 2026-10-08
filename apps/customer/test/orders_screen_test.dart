import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_customer/app_state.dart';
import 'package:fixgo_customer/screens/orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends FixGoApiClient {
  _Api() : super(baseUrl: 'https://api.example.com');

  Object? failWith;
  int calls = 0;

  @override
  Future<List<Order>> listMyOrders() async {
    calls++;
    final error = failWith;
    if (error != null) throw error;
    return const [];
  }
}

Future<void> _pump(WidgetTester tester, _Api api) async {
  await tester.pumpWidget(
    AppStateScope(
      state: AppState(api: api),
      child: const MaterialApp(home: OrdersScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('no orders yet tells the customer where to start',
      (tester) async {
    await _pump(tester, _Api());
    expect(find.text('ยังไม่มีงาน'), findsOneWidget);
    expect(
      find.text('กดเรียกช่างได้ที่หน้าแรก งานที่เรียกจะแสดงที่นี่'),
      findsOneWidget,
    );
  });

  testWidgets('a failed load is not shown as "no orders" and can retry',
      (tester) async {
    final api = _Api()
      ..failWith = ApiException(503, 'เชื่อมต่อไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่');
    await _pump(tester, api);
    expect(find.text('โหลดไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ยังไม่มีงาน'), findsNothing);

    api.failWith = null;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, 2);
    expect(find.text('ยังไม่มีงาน'), findsOneWidget);
  });
}
