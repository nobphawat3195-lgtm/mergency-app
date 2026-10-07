import 'dart:async';

import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('userMessageFor', () {
    test('keeps Thai messages from the server', () {
      expect(
        userMessageFor(ApiException(409, 'ราคาเปลี่ยนแล้ว กรุณาตรวจอีกครั้ง')),
        'ราคาเปลี่ยนแล้ว กรุณาตรวจอีกครั้ง',
      );
    });

    test('never shows English or raw errors', () {
      expect(
        userMessageFor(ApiException(500, 'Internal server error')),
        'ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง',
      );
      expect(
        userMessageFor(ApiException(400, 'Bad Request')),
        'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
      );
      expect(
        userMessageFor(const FormatException('Unexpected character')),
        'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
      );
      expect(
        userMessageFor(TimeoutException('x')),
        'การเชื่อมต่อใช้เวลานาน กรุณาลองใหม่อีกครั้ง',
      );
    });
  });

  group('AsyncStateView', () {
    Widget view(Future<List<String>> future, {VoidCallback? onRetry}) => _app(
          AsyncStateView<List<String>>(
            future: future,
            onRetry: onRetry ?? () {},
            isEmpty: (items) => items.isEmpty,
            empty: const EmptyStateView(
              title: 'ยังไม่มีงาน',
              message: 'กดเรียกช่างได้ที่หน้าแรก',
            ),
            builder: (context, items) =>
                Column(children: [for (final i in items) Text(i)]),
          ),
        );

    testWidgets('loading shows a spinner', (tester) async {
      final pending = Completer<List<String>>();
      await tester.pumpWidget(view(pending.future));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(['งาน 1']);
      await tester.pump();
      expect(find.text('งาน 1'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('empty shows what to do next', (tester) async {
      await tester.pumpWidget(view(Future.value(const [])));
      await tester.pump();
      expect(find.text('ยังไม่มีงาน'), findsOneWidget);
      expect(find.text('กดเรียกช่างได้ที่หน้าแรก'), findsOneWidget);
    });

    testWidgets('error shows a Thai message and retry, never the raw error',
        (tester) async {
      var retried = 0;
      final failing = Completer<List<String>>();
      await tester.pumpWidget(
        view(failing.future, onRetry: () => retried++),
      );
      failing.completeError(ApiException(500, 'Internal server error'));
      await tester.pump();
      expect(find.text('โหลดไม่สำเร็จ'), findsOneWidget);
      expect(
        find.text('ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง'),
        findsOneWidget,
      );
      expect(find.textContaining('Internal'), findsNothing);
      await tester.tap(find.text('ลองใหม่'));
      expect(retried, 1);
    });

    testWidgets('reloading keeps the previous data on screen', (tester) async {
      final future = ValueNotifier<Future<List<String>>>(
        Future.value(['งานเดิม']),
      );
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<Future<List<String>>>(
            valueListenable: future,
            builder: (context, value, _) => AsyncStateView<List<String>>(
              future: value,
              onRetry: () {},
              builder: (context, items) =>
                  Column(children: [for (final i in items) Text(i)]),
            ),
          ),
        ),
      );
      await tester.pump();
      final next = Completer<List<String>>();
      future.value = next.future;
      await tester.pump();
      expect(find.text('งานเดิม'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      next.complete(['งานใหม่']);
      await tester.pump();
      await tester.pump();
      expect(find.text('งานใหม่'), findsOneWidget);
    });
  });

  testWidgets('BusyButton blocks double taps while waiting', (tester) async {
    var calls = 0;
    final done = Completer<void>();
    await tester.pumpWidget(
      _app(
        BusyButton(
          label: 'ส่ง',
          onPressed: () {
            calls++;
            return done.future;
          },
        ),
      ),
    );
    await tester.tap(find.text('ส่ง'));
    await tester.pump();
    await tester.tap(find.text('ส่ง'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    done.complete();
    await tester.pump();
    await tester.tap(find.text('ส่ง'));
    expect(calls, 2);
  });

  testWidgets('result snack bar is Thai on failure', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showResultSnackBar(
              context,
              error: ApiException(502, 'Bad Gateway'),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(
      find.text('ระบบขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง'),
      findsOneWidget,
    );
  });
}
