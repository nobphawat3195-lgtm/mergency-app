import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_customer/screens/tracking/suggestion_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends FixGoApiClient {
  _Api() : super(baseUrl: 'https://api.example.com');

  List<String>? choices;
  String? text;

  @override
  Future<void> sendServiceSuggestion(
    String orderId, {
    required List<String> choices,
    String? otherText,
  }) async {
    this.choices = choices;
    text = otherText;
  }
}

Future<List<bool>> _pump(WidgetTester tester, _Api api) async {
  final done = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SuggestionCard(api: api, orderId: 'o1', onDone: done.add),
        ),
      ),
    ),
  );
  return done;
}

void main() {
  testWidgets('sends the picked quick options and free text', (tester) async {
    final api = _Api();
    final done = await _pump(tester, api);

    final send = find.widgetWithText(FilledButton, 'ส่งความเห็น');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.tap(find.text('ราคาถูกลง'));
    await tester.tap(find.text('เพิ่มบริการรถยก'));
    await tester.enterText(find.byType(TextField), 'อยากให้มีล้างรถ');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();

    // ส่งตามลำดับตัวเลือก ไม่ใช่ลำดับที่แตะ
    expect(api.choices, ['TOW_TRUCK', 'LOWER_PRICE']);
    expect(api.text, 'อยากให้มีล้างรถ');
    expect(done, [true]);
  });

  testWidgets('can be skipped', (tester) async {
    final api = _Api();
    final done = await _pump(tester, api);
    await tester.tap(find.text('ข้าม'));
    expect(done, [false]);
    expect(api.choices, isNull);
  });

  test('order exposes the suggestion answer only when sent', () {
    Map<String, dynamic> json(Object? suggestion) => {
          'id': 'o1',
          'orderNo': 'FG-1',
          'status': 'COMPLETED',
          'priceEstimated': 1,
          'pickupLat': 0,
          'pickupLng': 0,
          'suggestion': suggestion,
        };
    expect(Order.fromJson(json(null)).suggestionSent, false);
    final sent = Order.fromJson(json({
      'choices': ['OTHER'],
      'otherText': 'x',
    }));
    expect(sent.suggestionSent, true);
    expect(sent.suggestionChoices, ['OTHER']);
  });
}
