import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// ทั้งสองแอปใช้ภาษาไทย: ปฏิทิน ตัวเลือกเวลา และปุ่มของระบบเป็นภาษาไทย
const fixGoLocale = Locale('th', 'TH');

const fixGoSupportedLocales = [fixGoLocale];

const fixGoLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// ปัดนาทีให้เป็น :00 หรือ :30 (ปัดขึ้นไปครึ่งชั่วโมงถัดไป) ใช้เป็นค่าเริ่มต้นของตัวเลือกเวลา
TimeOfDay roundToHalfHour(TimeOfDay time) {
  if (time.minute == 0 || time.minute == 30) return time;
  if (time.minute < 30) return TimeOfDay(hour: time.hour, minute: 30);
  return TimeOfDay(hour: (time.hour + 1) % 24, minute: 0);
}

/// ตัวเลือกเวลาแบบ 24 ชั่วโมง เริ่มที่นาที :00 หรือ :30
Future<TimeOfDay?> showFixGoTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: roundToHalfHour(initialTime),
    helpText: helpText,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
}
