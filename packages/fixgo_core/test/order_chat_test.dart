import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ChatApi extends FixGoApiClient {
  _ChatApi({required this.canSend, List<ChatMessage>? messages})
      : messages = messages ?? [],
        super(baseUrl: 'https://api.example.com');

  final bool canSend;
  final List<ChatMessage> messages;
  final sent = <String>[];
  bool fail = false;

  @override
  Future<({bool canSend, List<ChatMessage> messages})> getOrderChat(
    String orderId,
  ) async {
    if (fail) throw ApiException(502, 'Bad Gateway');
    return (canSend: canSend, messages: List.of(messages));
  }

  @override
  Future<ChatMessage> sendOrderMessage(
    String orderId, {
    String? text,
    String? imageUrl,
  }) async {
    sent.add(text!);
    final message = ChatMessage(
      id: 'm${messages.length}',
      sender: ChatSender.customer,
      text: text,
      createdAt: DateTime(2026, 10, 6, 9, 5),
    );
    messages.add(message);
    return message;
  }
}

ChatMessage _msg(String id, ChatSender sender, String text) => ChatMessage(
      id: id,
      sender: sender,
      text: text,
      createdAt: DateTime(2026, 10, 6, 9, 0),
    );

Future<void> _pump(WidgetTester tester, _ChatApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OrderChatScreen(
        api: api,
        orderId: 'o1',
        me: ChatSender.customer,
        title: 'แชทกับช่างเอ',
        pollInterval: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => ChatChime.enabled = false);

  testWidgets('shows both sides and sends a trimmed message', (tester) async {
    final api = _ChatApi(
      canSend: true,
      messages: [_msg('1', ChatSender.provider, 'อีก 10 นาทีถึงครับ')],
    );
    await _pump(tester, api);
    expect(find.text('อีก 10 นาทีถึงครับ'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  รอที่ปั๊มครับ  ');
    await tester.tap(find.byTooltip('ส่ง'));
    await tester.pump();
    expect(api.sent, ['รอที่ปั๊มครับ']);
    expect(find.text('รอที่ปั๊มครับ'), findsOneWidget);

    // ช่องว่างล้วนไม่ส่ง
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('ส่ง'));
    await tester.pump();
    expect(api.sent, hasLength(1));
  });

  testWidgets('after the job ends the chat is read-only', (tester) async {
    final api = _ChatApi(
      canSend: false,
      messages: [_msg('1', ChatSender.customer, 'ขอบคุณครับ')],
    );
    await _pump(tester, api);
    expect(find.text('ขอบคุณครับ'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('งานนี้จบแล้วหรือยังไม่มีช่างรับ แชทอ่านได้อย่างเดียว'),
      findsOneWidget,
    );
  });

  testWidgets('a failed load offers retry instead of a read-only chat',
      (tester) async {
    final api = _ChatApi(
      canSend: true,
      messages: [_msg('1', ChatSender.provider, 'ถึงแล้วครับ')],
    )..fail = true;
    await _pump(tester, api);
    expect(find.text('โหลดแชทไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('Bad Gateway'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('งานนี้จบแล้วหรือยังไม่มีช่างรับ แชทอ่านได้อย่างเดียว'),
      findsNothing,
    );

    api.fail = false;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pump();
    await tester.pump();
    expect(find.text('ถึงแล้วครับ'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('badge button shows unread count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body:
              ChatBadgeButton(label: 'แชทกับช่าง', unread: 2, onPressed: () {}),
        ),
      ),
    );
    expect(find.text('แชทกับช่าง (2 ใหม่)'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  test('parses chat fields on orders', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'sender': 'PROVIDER',
      'text': null,
      'imageUrl': 'https://cdn.example/orders/u/a.jpg',
      'createdAt': '2026-10-06T02:00:00.000Z',
    });
    expect(message.sender, ChatSender.provider);
    expect(message.imageUrl, isNotNull);
  });
}
