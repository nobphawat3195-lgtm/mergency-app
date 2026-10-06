import 'package:fixgo_core/fixgo_core.dart';
import 'package:fixgo_provider/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

Order _order(String id, int unread) => Order.fromJson({
      'id': id,
      'orderNo': 'FG-$id',
      'status': 'EN_ROUTE',
      'priceEstimated': 50000,
      'pickupLat': 13.7,
      'pickupLng': 100.5,
      'chatOpen': true,
      'chatUnread': unread,
    });

void main() {
  test('chimes once per new customer message across screens', () {
    final state = ProviderAppState(
      api: FixGoApiClient(baseUrl: 'https://api.example.com'),
    );
    addTearDown(state.dispose);

    // ครั้งแรกที่เห็นงาน ยังไม่ดัง (ข้อความเก่าก่อนเปิดแอป)
    expect(state.trackChatUnread([_order('1', 2)]), false);
    // หน้าอื่น poll ได้ค่าเดิม ไม่ดังซ้ำ
    expect(state.trackChatUnread([_order('1', 2)]), false);
    expect(state.trackChatUnread([_order('1', 3)]), true);
    // เปิดอ่านแล้วเป็น 0 แล้วมีใหม่อีก
    expect(state.trackChatUnread([_order('1', 0)]), false);
    expect(state.trackChatUnread([_order('1', 1)]), true);
  });
}
