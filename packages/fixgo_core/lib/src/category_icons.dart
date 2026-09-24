import 'package:flutter/material.dart';

/// ไอคอนหมวดบริการแบบ 3D ชุดเดียวกันทั้งแอป (โทนน้ำเงิน-ส้ม ภาพสมจริง)
///
/// - ชุดหลัก 8 รูป: ซ่อมรถ แบตเตอรี่ ยาง กุญแจ น้ำมัน รถยก รถ EV ตรวจรถ
///   ได้จากเจ้าของโปรเจกต์ ตัดพื้นหลังเป็นโปร่งใสแล้ว (ไฟล์ละ 384x384)
/// - `electrical.png` (สายฟ้า), `emergency.png` (ไซเรน), `technician.png` (ช่าง)
///   มาจาก Microsoft Fluent Emoji (MIT) ใช้ชั่วคราวจนกว่าจะมีรูปชุดเดียวกัน
///   สัญญาอนุญาตอยู่ที่ assets/icons/licenses/fluentui-emoji-LICENSE.txt
///
/// map จาก iconKey ที่ backend ส่งมา เป็น path รูปภายในแพ็กเกจ ใช้กับ Image.asset
/// เสมอ (ไม่ใช่ AssetImage เฉยๆ) เพราะต้องมี prefix "packages/fixgo_core/" ให้ถูกต้อง
String categoryIconAsset(String iconKey) {
  const base = 'packages/fixgo_core/assets/icons';
  switch (iconKey) {
    case 'mechanic':
    case 'electrical':
    case 'battery':
    case 'tire':
    case 'key':
    case 'tow':
    case 'fuel':
    case 'ev':
    case 'inspection':
      return '$base/$iconKey.png';
    default:
      return '$base/mechanic.png';
  }
}

/// widget ไอคอนหมวดบริการขนาดคงที่ ใช้ในลิสต์และกริด
class CategoryIconArt extends StatelessWidget {
  const CategoryIconArt({super.key, required this.iconKey, this.size = 58});

  final String iconKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      categoryIconAsset(iconKey),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// ไฟไซเรนฉุกเฉิน ใช้กับการ์ด "เรียกช่างฉุกเฉิน" หน้าแรก
const emergencyIconAsset = 'packages/fixgo_core/assets/icons/emergency.png';

/// ภาพช่าง 3D ใช้เป็น avatar ช่างเมื่อยังไม่มีรูปโปรไฟล์จริง
const technicianIconAsset = 'packages/fixgo_core/assets/icons/technician.png';

/// โลโก้ FixGo (หมุดตำแหน่ง + ประแจ บนพื้นส้ม)
const brandLogoAsset = 'packages/fixgo_core/assets/brand/logo_mark.png';
