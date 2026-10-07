import 'package:fixgo_core/fixgo_core.dart';

/// อาการรถที่ลูกค้าเลือกได้จากหน้าแรก คนที่รถเสียรู้ว่า "สตาร์ทไม่ติด"
/// แต่มักไม่รู้ว่าต้องเรียกช่างหมวดไหน ระบบจึงเลือกหมวดและบริการย่อยให้
///
/// [categorySlug] และ [subServiceKeyword] ต้องตรงกับข้อมูลใน backend/prisma/seed.ts
/// ถ้าหาบริการย่อยไม่เจอ หน้าจองจะให้ลูกค้าเลือกบริการย่อยเองตามปกติ
class CarSymptom {
  const CarSymptom({
    required this.label,
    required this.iconKey,
    required this.categorySlug,
    required this.subServiceKeyword,
  });

  final String label;

  /// key ของ [categoryIconAsset]
  final String iconKey;
  final String categorySlug;
  final String subServiceKeyword;

  /// ข้อความเริ่มต้นในช่องรายละเอียด ช่างเห็นอาการตั้งแต่ตอนรับงาน
  String get note => 'อาการ: $label';
}

/// อาการที่พบบ่อยข้างทาง เรียงจากที่เจอบ่อยสุด อาการที่ไม่ชัดเจนใช้บริการ
/// "เรียกช่างให้ไปดูก่อน" ซึ่งช่างจะแจ้งราคาจริงหน้างานให้ลูกค้ายืนยันก่อนซ่อม
const carSymptoms = <CarSymptom>[
  CarSymptom(
    label: 'แบตหมด สตาร์ทไม่ติด',
    iconKey: 'battery',
    categorySlug: 'battery',
    subServiceKeyword: 'จั๊ม',
  ),
  CarSymptom(
    label: 'ยางแบน ยางรั่ว',
    iconKey: 'tire',
    categorySlug: 'tire',
    subServiceKeyword: 'เรียกช่างให้ไปดูก่อน',
  ),
  CarSymptom(
    label: 'ลืมกุญแจไว้ในรถ',
    iconKey: 'key',
    categorySlug: 'locksmith',
    subServiceKeyword: 'สะเดาะล็อค',
  ),
  CarSymptom(
    label: 'น้ำมันหมด',
    iconKey: 'fuel',
    categorySlug: 'fuel-delivery',
    subServiceKeyword: 'ส่งน้ำมัน',
  ),
  CarSymptom(
    label: 'ไฟเตือนขึ้นหน้าปัด',
    iconKey: 'electrical',
    categorySlug: 'car-mechanic',
    subServiceKeyword: 'ไฟเตือน',
  ),
  CarSymptom(
    label: 'รถดับกลางทาง',
    iconKey: 'mechanic',
    categorySlug: 'car-mechanic',
    subServiceKeyword: 'ดับกลางทาง',
  ),
  CarSymptom(
    label: 'รถชน ต้องยก/ลาก',
    iconKey: 'tow',
    categorySlug: 'towing',
    subServiceKeyword: 'รถสไลด์ใกล้ฉัน',
  ),
  CarSymptom(
    label: 'รถ EV ชาร์จไม่เข้า',
    iconKey: 'ev',
    categorySlug: 'ev-assist',
    subServiceKeyword: 'ชาร์จไม่เข้า',
  ),
  CarSymptom(
    label: 'ไม่แน่ใจ ให้ช่างดู',
    iconKey: 'mechanic',
    categorySlug: 'car-mechanic',
    subServiceKeyword: 'เรียกช่างให้ไปดูก่อน',
  ),
];

ServiceCategory? categoryForSymptom(
  CarSymptom symptom,
  List<ServiceCategory> categories,
) {
  for (final category in categories) {
    if (category.slug == symptom.categorySlug) return category;
  }
  return null;
}

/// อาการที่ยังกดได้: หมวดของอาการต้องเปิดอยู่ (แอดมินปิดหมวดที่ยังไม่มีช่าง
/// API จะไม่ส่งหมวดนั้นมา) ส่งรายการหมวดที่โหลดแล้วเท่านั้น
List<CarSymptom> openSymptoms(List<ServiceCategory> categories) => carSymptoms
    .where((symptom) => categoryForSymptom(symptom, categories) != null)
    .toList();
