import 'dart:async';
import 'dart:convert';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  FixGoApiClient clientWith(
    Future<http.StreamedResponse> Function(http.BaseRequest) handler,
  ) {
    return FixGoApiClient(
      baseUrl: 'https://api.fixgo.test',
      streamClientFactory: () => MockClient.streaming(
        (request, _) => handler(request),
      ),
    )..accessToken = 'token-1';
  }

  test('parses order and ping events from the SSE stream', () async {
    late http.BaseRequest seen;
    final api = clientWith((request) async {
      seen = request;
      const body = 'event: order\nid: 1\ndata: {"type":"MATCHED"}\n\n'
          ': comment\n'
          'event: ping\ndata: {}\n\n'
          'event: order\ndata: {"type":"LOCATION"}\n\n';
      return http.StreamedResponse(
        Stream.fromIterable([utf8.encode(body)]),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final events = await api.orderEvents('order_1').toList();

    expect(events, ['MATCHED', 'PING', 'LOCATION']);
    expect(seen.url.toString(),
        'https://api.fixgo.test/api/orders/order_1/events');
    expect(seen.headers['Authorization'], 'Bearer token-1');
    expect(seen.headers['Accept'], 'text/event-stream');
  });

  test('handles events split across network chunks', () async {
    final api = clientWith((request) async {
      final chunks = [
        'event: or',
        'der\ndata: {"type":"EN_',
        'ROUTE"}\n',
        '\n',
      ].map(utf8.encode);
      return http.StreamedResponse(Stream.fromIterable(chunks), 200);
    });
    expect(await api.orderEvents('o').toList(), ['EN_ROUTE']);
  });

  test('reports a non-200 response as an error so the screen can retry',
      () async {
    final api = clientWith(
      (request) async => http.StreamedResponse(const Stream.empty(), 404),
    );
    await expectLater(
      api.orderEvents('o'),
      emitsError(isA<ApiException>()
          .having((error) => error.statusCode, 'statusCode', 404)),
    );
  });
}
