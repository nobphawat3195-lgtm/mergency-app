import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('order splits close photos into car and receipt', () {
    final order = Order.fromJson({
      'id': 'o1',
      'orderNo': 'FG-1',
      'status': 'COMPLETED',
      'priceEstimated': 50000,
      'pickupLat': 13.7,
      'pickupLng': 100.5,
      'closePhotos': [
        {'kind': 'CAR', 'url': 'https://cdn/orders/p/car1.jpg'},
        {'kind': 'RECEIPT', 'url': 'https://cdn/orders/p/r1.jpg'},
        {'kind': 'CAR', 'url': 'https://cdn/orders/p/car2.jpg'},
      ],
    });
    expect(order.carPhotoUrls, [
      'https://cdn/orders/p/car1.jpg',
      'https://cdn/orders/p/car2.jpg',
    ]);
    expect(order.receiptPhotoUrls, ['https://cdn/orders/p/r1.jpg']);
  });

  testWidgets('photo strip removes a photo when editable', (tester) async {
    final removed = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoStrip(
            label: 'รูปรถ',
            urls: const ['https://cdn/a.jpg', 'https://cdn/b.jpg'],
            onRemove: removed.add,
          ),
        ),
      ),
    );
    expect(find.text('รูปรถ'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('ลบรูป').last);
    expect(removed, [1]);
  });
}
