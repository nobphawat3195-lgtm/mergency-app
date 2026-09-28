import 'dart:io';

import 'package:fixgo_customer/symptoms.dart';
import 'package:flutter_test/flutter_test.dart';

/// อาการแต่ละข้อต้องชี้ไปยังหมวดและบริการย่อยที่มีอยู่จริงใน seed ของ backend
/// ถ้ามีคนเปลี่ยนชื่อบริการใน seed แล้วลืมแก้ที่นี่ test นี้จะแจ้งทันที
void main() {
  final seed = File('../../backend/prisma/seed.ts').readAsStringSync();

  /// แยก seed เป็นช่วงของแต่ละหมวด: ตั้งแต่ slug หมวดนั้นจนถึง slug หมวดถัดไป
  Map<String, String> categoryBlocks() {
    final matches =
        RegExp(r"^    slug: '([a-z0-9-]+)',", multiLine: true).allMatches(seed);
    final list = matches.toList();
    return {
      for (var i = 0; i < list.length; i++)
        list[i].group(1)!: seed.substring(
          list[i].start,
          i + 1 < list.length ? list[i + 1].start : seed.length,
        ),
    };
  }

  test('ทุกอาการชี้ไปยังบริการที่มีอยู่จริง', () {
    final blocks = categoryBlocks();
    for (final symptom in carSymptoms) {
      final block = blocks[symptom.categorySlug];
      expect(block, isNotNull, reason: 'ไม่พบหมวด ${symptom.categorySlug}');
      final names = RegExp(r"name: '([^']+)'")
          .allMatches(block!)
          .map((m) => m.group(1)!)
          .skip(1); // ชื่อแรกคือชื่อหมวด
      expect(
        names.where((name) => name.contains(symptom.subServiceKeyword)),
        hasLength(1),
        reason: '${symptom.label}: คำค้น "${symptom.subServiceKeyword}" '
            'ต้องตรงกับบริการย่อยเดียวในหมวด ${symptom.categorySlug}',
      );
    }
  });

  test('ข้อความอาการไม่ซ้ำกัน', () {
    final labels = carSymptoms.map((s) => s.label).toSet();
    expect(labels, hasLength(carSymptoms.length));
  });
}
