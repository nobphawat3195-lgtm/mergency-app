import 'package:fixgo_provider/working_hours.dart';
import 'package:flutter_test/flutter_test.dart';

/// เวลาไทย hh:mm ของวันหนึ่ง (UTC+7) แปลงเป็น DateTime UTC
DateTime bangkok(int hour, int minute) =>
    DateTime.utc(2026, 10, 6, hour, minute).subtract(const Duration(hours: 7));

void main() {
  test('minute of day follows Bangkok time, not the device zone', () {
    expect(bangkokMinuteOfDay(DateTime.utc(2026, 9, 20, 0, 30)), 7 * 60 + 30);
    expect(bangkokMinuteOfDay(bangkok(17, 13)), 17 * 60 + 13);
  });

  test('working window matches the backend rule, including midnight', () {
    expect(isWithinWorkingHours(1230, 1439, 17 * 60 + 13), false);
    expect(isWithinWorkingHours(1230, 1439, 1439), true);
    expect(isWithinWorkingHours(18 * 60, 6 * 60, 3 * 60), true);
    expect(isWithinWorkingHours(18 * 60, 6 * 60, 12 * 60), false);
    for (final minute in [0, 720, 1439]) {
      expect(isWithinWorkingHours(0, 1439, minute), true);
    }
  });

  test('labels show the range clearly in 24-hour time', () {
    expect(workingHoursLabel(0, 1439), 'ตลอดเวลา');
    expect(workingHoursLabel(480, 1200), '08:00-20:00');
    expect(workingHoursSentence(1230, 1439), 'รับงาน 20:30 ถึง 23:59');
    expect(
      workingHoursSentence(18 * 60, 6 * 60),
      'รับงาน 18:00 ถึง 06:00 (ข้ามเที่ยงคืน)',
    );
    expect(WorkingHoursPreset.of(480, 1200), WorkingHoursPreset.day);
    expect(WorkingHoursPreset.of(1230, 1439), WorkingHoursPreset.custom);
  });

  group('quick extend from now', () {
    test('outside the window starts now', () {
      final next = extendWorkingHours(
        open: 1230,
        close: 1439,
        by: const Duration(hours: 2),
        now: bangkok(17, 13),
      );
      expect(next, (open: 17 * 60 + 13, close: 19 * 60 + 13));
    });

    test('inside the window keeps the start and moves the end', () {
      final next = extendWorkingHours(
        open: 8 * 60,
        close: 20 * 60,
        by: const Duration(hours: 4),
        now: bangkok(19, 0),
      );
      expect(next, (open: 8 * 60, close: 23 * 60));
    });

    test('wraps past midnight', () {
      final next = extendWorkingHours(
        open: 8 * 60,
        close: 20 * 60,
        by: const Duration(hours: 2),
        now: bangkok(23, 0),
      );
      expect(next, (open: 23 * 60, close: 60));
      expect(isWithinWorkingHours(next.open, next.close, 30), true);
    });

    test('until midnight ends at 23:59', () {
      final next = extendWorkingHours(open: 0, close: 1439, now: bangkok(9, 5));
      expect(next, (open: 9 * 60 + 5, close: 1439));
    });
  });
}
