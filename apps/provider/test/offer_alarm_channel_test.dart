import 'package:fixgo_provider/offer_alarm_channel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one notification id per job, stable across isolates', () {
    const orderId = '0b5f45aa-16a3-4b7b-8c7e-ecf8f1122821';
    expect(offerNotificationId(orderId), offerNotificationId(orderId));
    expect(offerNotificationId(orderId), isNot(offerNotificationId('other')));
    expect(offerNotificationId(orderId), inInclusiveRange(0, 0x7fffffff));
  });

  test('a new job rings like an alarm until answered or expired', () {
    final details = offerAlarmAndroidDetails(
      title: 'มีงานใหม่ใกล้คุณ',
      timeLeft: const Duration(seconds: 170),
    );
    expect(details.channelId, 'fixgo_offer_alarm');
    expect(details.fullScreenIntent, isTrue);
    expect(details.category, AndroidNotificationCategory.alarm);
    expect(details.importance, Importance.max);
    expect(details.ongoing, isTrue);
    expect(details.autoCancel, isFalse);
    expect(details.timeoutAfter, 170000);
    // FLAG_INSISTENT = 4: เสียงวนจนกว่าจะปิด
    expect(details.additionalFlags, [4]);
    expect(details.audioAttributesUsage, AudioAttributesUsage.alarm);
    expect(
      (details.sound as RawResourceAndroidNotificationSound).sound,
      'offer_alarm',
    );
    expect(details.actions!.map((a) => (a.id, a.title)), [
      ('accept', 'รับงาน'),
      ('reject', 'ปฏิเสธ'),
    ]);
    // รับงานต้องเปิดแอป ปฏิเสธส่งจากเบื้องหลังได้เลย
    expect(details.actions!.first.showsUserInterface, isTrue);
    expect(details.actions!.last.showsUserInterface, isFalse);
  });

  test('iOS uses the bundled 30 s alarm sound, time sensitive', () {
    final details = offerAlarmDarwinDetails('order_1');
    expect(details.sound, 'offer_alarm.caf');
    expect(details.interruptionLevel, InterruptionLevel.timeSensitive);
    expect(details.threadIdentifier, 'order_1');
  });
}
