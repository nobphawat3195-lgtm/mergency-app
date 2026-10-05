import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

/// เปิดหน้าปักหมุดของแอปลูกค้า (ระบุแอปให้ OpenStreetMap ตามนโยบาย tile)
Future<LocationResult?> pickCustomerLocationOnMap(
  BuildContext context, {
  LocationResult? initial,
  String title = 'ปักหมุดจุดนัดหมาย',
}) =>
    pickLocationOnMap(
      context,
      initial: initial,
      title: title,
      userAgentPackageName: 'com.fixgo.fixgo_customer',
    );

/// ให้ลูกค้าเลือกว่าจะใช้ GPS หรือปักหมุดเอง (เผื่อเรียกช่างให้คนอื่น หรือ GPS ใช้ไม่ได้)
///
/// GPS ไม่สำเร็จจะพาไปหน้าปักหมุดต่อทันที ไม่ให้ลูกค้าติดอยู่ที่ปุ่มหมุนค้าง
/// คืน null เมื่อผู้ใช้ยกเลิก
Future<LocationResult?> chooseCustomerLocation(
  BuildContext context, {
  LocationResult? current,
  String title = 'ปักหมุดจุดนัดหมาย',
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.my_location, color: FixGoColors.accent),
            title: const Text('ใช้ตำแหน่งปัจจุบัน (GPS)'),
            onTap: () => Navigator.of(sheetContext).pop('gps'),
          ),
          ListTile(
            leading:
                const Icon(Icons.push_pin_outlined, color: FixGoColors.accent),
            title: const Text('ปักหมุดบนแผนที่เอง'),
            subtitle: const Text('เช่น เรียกช่างให้คนอื่น หรือ GPS ไม่ตรง'),
            onTap: () => Navigator.of(sheetContext).pop('map'),
          ),
          const SizedBox(height: FixGoSpacing.sm),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == 'map') {
    return pickCustomerLocationOnMap(context, initial: current, title: title);
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Text('กำลังหาตำแหน่ง...'),
      duration: Duration(seconds: 2),
    ),
  );
  try {
    return await LocationService.getCurrentLocation();
  } on LocationException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    if (!context.mounted) return null;
    return pickCustomerLocationOnMap(context, initial: current, title: title);
  }
}
