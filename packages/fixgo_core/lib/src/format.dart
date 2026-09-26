const _thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

/// วันเวลาแบบไทย เช่น "24 ก.ย. 2569 14:30" (ปี พ.ศ.)
String formatThaiDateTime(DateTime value) {
  final local = value.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_thaiMonths[local.month - 1]} ${local.year + 543} '
      '${local.hour}:$minute';
}

/// ตัวเลขมีคอมมา เช่น 125000 -> "125,000"
String formatThousands(num value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
