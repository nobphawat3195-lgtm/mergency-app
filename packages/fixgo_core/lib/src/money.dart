import 'package:intl/intl.dart';

final NumberFormat _bahtFormat = NumberFormat('#,##0', 'th_TH');

/// แปลงจำนวนเงินหน่วยสตางค์ (ตามที่ backend เก็บ) เป็นข้อความบาท เช่น 117700 -> "฿1,177"
String formatSatang(int satang) {
  final baht = satang / 100;
  final hasFraction = satang % 100 != 0;
  if (hasFraction) {
    return '฿${NumberFormat('#,##0.00', 'th_TH').format(baht)}';
  }
  return '฿${_bahtFormat.format(baht)}';
}

/// แปลงบาทเป็นสตางค์สำหรับส่งกลับไป backend
int bahtToSatang(double baht) => (baht * 100).round();
