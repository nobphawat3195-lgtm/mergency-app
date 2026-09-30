import 'dart:async';
import 'dart:convert';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('approval sends the version and amount displayed to the customer',
      () async {
    final api = FixGoApiClient(
      baseUrl: 'https://api.example.com',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/orders/order-1/quote/approve');
        expect(jsonDecode(request.body),
            {'quoteVersion': 2, 'priceProposed': 149000});
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.dispose);
    await api.approveQuote('order-1', quoteVersion: 2, priceProposed: 149000);
  });

  test('a hanging request returns an actionable timeout without retrying',
      () async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final api = FixGoApiClient(
      baseUrl: 'https://api.example.com',
      requestTimeout: const Duration(milliseconds: 5),
      httpClient: MockClient((_) {
        calls++;
        return pending.future;
      }),
    );
    addTearDown(api.dispose);
    await expectLater(
        api.listCategories(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 408)));
    expect(calls, 1);
    pending.complete(http.Response('[]', 200));
  });

  test('connection failures become ApiException for existing screen handlers',
      () async {
    final api = FixGoApiClient(
      baseUrl: 'https://api.example.com',
      httpClient:
          MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(api.dispose);
    await expectLater(
        api.listCategories(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 503)));
  });

  test('order parsing preserves the quote version', () {
    final order = Order.fromJson({
      'id': 'order-1',
      'orderNo': 'FG-1',
      'status': 'EN_ROUTE',
      'priceEstimated': 149000,
      'priceProposed': 149000,
      'quoteVersion': 3,
      'quoteStatus': 'PENDING',
      'pickupLat': 13.7,
      'pickupLng': 100.5,
    });
    expect(order.quoteVersion, 3);
  });
}
