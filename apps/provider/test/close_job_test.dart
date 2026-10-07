import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:fixgo_provider/screens/close_job_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('closing a job requires at least one car photo', (tester) async {
    final state = ProviderAppState(
      api: FixGoApiClient(baseUrl: 'https://api.example.com'),
    );
    addTearDown(state.dispose);
    final order = Order.fromJson({
      'id': 'o1',
      'orderNo': 'FG-1',
      'status': 'IN_PROGRESS',
      'priceEstimated': 50000,
      'priceProposed': 80000,
      'quoteStatus': 'APPROVED',
      'pickupLat': 13.7,
      'pickupLng': 100.5,
    });
    await tester.pumpWidget(
      ProviderAppScope(
        state: state,
        child: MaterialApp(home: CloseJobScreen(order: order)),
      ),
    );
    expect(find.text('รูปรถหลังซ่อมเสร็จ (บังคับ 1-5 รูป)'), findsOneWidget);
    expect(
        find.text('ใบเสร็จ / สลิป (ไม่บังคับ สูงสุด 3 รูป)'), findsOneWidget);
    expect(find.text('แนบรูป (0/5)'), findsOneWidget);
    final submit = tester.widget<FixGoButton>(find.byType(FixGoButton));
    expect(submit.onPressed, isNull);
  });
}
