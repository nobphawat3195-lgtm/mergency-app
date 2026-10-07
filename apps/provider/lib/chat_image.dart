import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// เลือกรูปแนบแชทจากคลังรูป ย่อให้กว้างไม่เกิน 1600px
///
/// ไม่เปิดกล้องจากในแอป (iOS ต้องมีคำอธิบายสิทธิ์กล้องเพิ่ม) ถ่ายด้วยกล้องเครื่องแล้วเลือกจากคลังรูปได้
Future<ChatImage?> pickChatImage(BuildContext context) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 80,
    maxWidth: 1600,
  );
  if (file == null) return null;
  final name = file.name.toLowerCase();
  return (
    bytes: await file.readAsBytes(),
    fileName: file.name,
    contentType: name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg',
  );
}

/// เปิดแชทกับลูกค้าของงานนี้ (ใช้ทั้งหน้าหลักและหน้างานของฉัน)
Future<void> openCustomerChat(
  BuildContext context, {
  required FixGoApiClient api,
  required Order order,
}) {
  final name = order.customerName;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OrderChatScreen(
        api: api,
        orderId: order.id,
        me: ChatSender.provider,
        title: name == null || name.isEmpty
            ? 'แชทกับลูกค้า ${order.orderNo}'
            : 'แชทกับคุณ$name',
        pickImage: pickChatImage,
      ),
    ),
  );
}
