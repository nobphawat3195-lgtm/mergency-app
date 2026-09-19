/// ไอคอนหมวดบริการแบบ 3D — จาก Microsoft Fluent Emoji (MIT License)
/// ที่มา: https://github.com/microsoft/fluentui-emoji
/// สัญญาอนุญาตเต็มอยู่ที่ assets/icons/licenses/fluentui-emoji-LICENSE.txt
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
