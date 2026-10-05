import 'dart:typed_data';

import 'file_save_io.dart' if (dart.library.js_interop) 'file_save_web.dart'
    as impl;

/// บันทึกรูป PNG ให้ผู้ใช้: เว็บดาวน์โหลดเป็นไฟล์ มือถือเปิดเมนูแชร์/บันทึกของเครื่อง
Future<void> savePngImage(Uint8List bytes, String fileName) =>
    impl.savePngImage(bytes, fileName);
