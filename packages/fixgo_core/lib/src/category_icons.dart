/// ไอคอนหมวดบริการแบบ 3D
///
/// - ส่วนใหญ่มาจาก Microsoft Fluent Emoji (MIT License)
///   ที่มา: https://github.com/microsoft/fluentui-emoji
///   สัญญาอนุญาตเต็มอยู่ที่ assets/icons/licenses/fluentui-emoji-LICENSE.txt
/// - `tow.png` (รถสไลด์บรรทุกรถ) และ `tire.png` (ยางรถยนต์) วาดขึ้นใหม่สำหรับ FixGo
///   เพราะ Fluent ไม่มีรูปที่สื่อความหมายตรง (เดิมใช้รถส่งของ/ล้อเกวียน ผู้ใช้เข้าใจผิด)
///
/// map จาก iconKey ที่ backend ส่งมา เป็น path รูปภายในแพ็กเกจ ใช้กับ Image.asset
/// เสมอ (ไม่ใช่ AssetImage เฉยๆ) เพราะต้องมี prefix "packages/fixgo_core/" ให้ถูกต้อง
String categoryIconAsset(String iconKey) {
  switch (iconKey) {
    case 'mechanic':
      return 'packages/fixgo_core/assets/icons/mechanic.png';
    case 'electrical':
      return 'packages/fixgo_core/assets/icons/electrical.png';
    case 'battery':
      return 'packages/fixgo_core/assets/icons/battery.png';
    case 'tire':
      return 'packages/fixgo_core/assets/icons/tire.png';
    case 'key':
      return 'packages/fixgo_core/assets/icons/key.png';
    case 'tow':
      return 'packages/fixgo_core/assets/icons/tow.png';
    case 'inspection':
      return 'packages/fixgo_core/assets/icons/inspection.png';
    default:
      return 'packages/fixgo_core/assets/icons/default.png';
  }
}

/// ไฟไซเรนฉุกเฉิน ใช้กับการ์ด "เรียกช่างฉุกเฉิน" หน้าแรก
const emergencyIconAsset = 'packages/fixgo_core/assets/icons/emergency.png';

/// ภาพช่าง 3D ใช้เป็น avatar ช่างเมื่อยังไม่มีรูปโปรไฟล์จริง
const technicianIconAsset = 'packages/fixgo_core/assets/icons/technician.png';

/// โลโก้ FixGo (หมุดตำแหน่ง + ประแจ บนพื้นส้ม)
const brandLogoAsset = 'packages/fixgo_core/assets/brand/logo_mark.png';
