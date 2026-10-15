import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// ช่องแจ้งเตือนงานใหม่ (Android) ชื่อต้องตรงกับ channelId ที่ backend ส่งมา
/// เสียงจาก res/raw/offer_alarm.wav ดังแบบนาฬิกาปลุก (ใช้ระดับเสียง Alarm ของเครื่อง)
const offerAlarmChannel = AndroidNotificationChannel(
  'fixgo_offer_alarm',
  'งานใหม่ (เสียงปลุก)',
  description:
      'เสียงปลุกและแสดงเต็มจอเมื่อมีงานใหม่ใกล้คุณ จนกว่าจะรับ/ปฏิเสธหรือหมดเวลา',
  importance: Importance.max,
  sound: RawResourceAndroidNotificationSound('offer_alarm'),
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

/// เสียงปลุกในแอป iOS (Runner bundle) ยาวไม่เกิน 30 วิ
const iosOfferSound = 'offer_alarm.caf';

/// Notification.FLAG_INSISTENT: เสียงวนซ้ำจนกว่าจะปิดแจ้งเตือน
const _flagInsistent = 4;

const acceptActionId = 'accept';
const rejectActionId = 'reject';

/// id ของแจ้งเตือนจากรหัสงาน (FNV-1a 31 บิต) ค่าเดิมทุก isolate ใช้ยกเลิกได้จากข้อความ push ถัดไป
int offerNotificationId(String orderId) {
  var hash = 0x811c9dc5;
  for (final unit in orderId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// แจ้งเตือนงานใหม่แบบนาฬิกาปลุก: เต็มจอบนจอล็อก เสียงวน ค้างจนตอบ หายเองเมื่อหมดเวลา
AndroidNotificationDetails offerAlarmAndroidDetails({
  required String title,
  required Duration timeLeft,
}) =>
    AndroidNotificationDetails(
      offerAlarmChannel.id,
      offerAlarmChannel.name,
      channelDescription: offerAlarmChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      timeoutAfter: timeLeft.inMilliseconds,
      additionalFlags: Int32List.fromList(const [_flagInsistent]),
      sound: offerAlarmChannel.sound,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      ticker: title,
      actions: const [
        AndroidNotificationAction(
          acceptActionId,
          'รับงาน',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          rejectActionId,
          'ปฏิเสธ',
          cancelNotification: true,
        ),
      ],
    );

DarwinNotificationDetails offerAlarmDarwinDetails(String orderId) =>
    DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      sound: iosOfferSound,
      interruptionLevel: InterruptionLevel.timeSensitive,
      threadIdentifier: orderId,
    );
