import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// มือถือ: เปิดเมนูแชร์ของเครื่อง ผู้ใช้เลือกบันทึกลงเครื่องหรือส่งต่อได้
Future<void> savePngImage(Uint8List bytes, String fileName) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [fileName],
    ),
  );
}
