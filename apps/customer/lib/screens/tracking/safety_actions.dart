import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// ปุ่มความปลอดภัยระหว่างรอช่าง: แชร์ลิงก์ติดตามให้ครอบครัว และเบอร์ฉุกเฉิน
class SafetyActions extends StatelessWidget {
  const SafetyActions({super.key, required this.api, required this.orderId});

  final FixGoApiClient api;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () =>
                showShareSheet(context, api: api, orderId: orderId),
            icon: const Icon(Icons.share_location_rounded),
            label: const Text('แชร์ให้ครอบครัว'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: FixGoColors.accent,
              side: const BorderSide(color: FixGoColors.accent),
            ),
          ),
        ),
        const SizedBox(width: FixGoSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => showSosSheet(context),
            icon: const Icon(Icons.sos_rounded),
            label: const Text('ฉุกเฉิน'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: FixGoColors.error,
              side: const BorderSide(color: FixGoColors.error),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _open(BuildContext context, Uri uri) async {
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('เปิดไม่สำเร็จ กรุณาลองอีกครั้ง')),
    );
  }
}

/// ขอลิงก์จาก backend แล้วให้เลือกส่งทาง LINE หรือคัดลอกไปวางที่อื่น
Future<void> showShareSheet(
  BuildContext context, {
  required FixGoApiClient api,
  required String orderId,
}) async {
  final String link;
  try {
    final shared = await api.shareOrder(orderId);
    final url =
        shared.url ?? (kIsWeb ? '${Uri.base.origin}${shared.path}' : null);
    if (url == null) {
      throw ApiException(503, 'ระบบยังไม่ได้ตั้งค่าเว็บสำหรับลิงก์ติดตาม');
    }
    link = url;
  } on ApiException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.message)));
    return;
  }
  if (!context.mounted) return;

  final message = 'ติดตามช่าง FixGo ที่กำลังมาช่วยฉันได้ที่ลิงก์นี้ $link';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'แชร์ให้ครอบครัวติดตาม',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'คนที่ได้ลิงก์จะเห็นสถานะงาน ตำแหน่งช่าง และทะเบียนรถช่าง '
              'โดยไม่ต้องล็อกอิน แต่ไม่เห็นเบอร์โทรหรือราคา '
              'ลิงก์ใช้ไม่ได้อีก 2 ชั่วโมงหลังจบงาน',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.md),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FixGoColors.surface,
                borderRadius: BorderRadius.circular(FixGoRadius.md),
              ),
              child: SelectableText(link, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: FixGoSpacing.md),
            FilledButton.icon(
              onPressed: () => _open(
                sheetContext,
                Uri.https('line.me', '/R/share', {'text': message}),
              ),
              icon: const Icon(Icons.chat_rounded),
              label: const Text('ส่งทาง LINE'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: const Color(0xFF06C755),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('คัดลอกลิงก์แล้ว')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('คัดลอกลิงก์'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await api.revokeOrderShare(orderId);
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('หยุดแชร์แล้ว ลิงก์เดิมเปิดไม่ได้อีก'),
                    ),
                  );
                } on ApiException catch (error) {
                  if (!sheetContext.mounted) return;
                  ScaffoldMessenger.of(sheetContext)
                      .showSnackBar(SnackBar(content: Text(error.message)));
                }
              },
              style: TextButton.styleFrom(foregroundColor: FixGoColors.error),
              child: const Text('หยุดแชร์ลิงก์นี้'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// เบอร์ฉุกเฉินของไทย กดแล้วโทรออกทันที
Future<void> showSosSheet(BuildContext context) {
  const numbers = [
    (number: '191', title: 'แจ้งเหตุด่วนเหตุร้าย', subtitle: 'ตำรวจ'),
    (number: '1669', title: 'เจ็บป่วยฉุกเฉิน', subtitle: 'รถพยาบาล'),
    (number: '1586', title: 'เหตุบนทางหลวง', subtitle: 'กรมทางหลวง'),
    (number: '1543', title: 'เหตุบนทางด่วน', subtitle: 'การทางพิเศษฯ'),
    (number: '199', title: 'ไฟไหม้ รถติดไฟ', subtitle: 'ดับเพลิง'),
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'เบอร์ฉุกเฉิน',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              'ถ้ามีคนบาดเจ็บหรือไม่ปลอดภัย โทรหาเจ้าหน้าที่ก่อน',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            for (final (index, item) in numbers.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: index == 0
                      ? FixGoColors.error
                      : FixGoColors.error.withValues(alpha: 0.1),
                  foregroundColor:
                      index == 0 ? Colors.white : FixGoColors.error,
                  child: const Icon(Icons.phone_in_talk_rounded),
                ),
                title: Text(
                  '${item.title} ${item.number}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(item.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    _open(sheetContext, Uri(scheme: 'tel', path: item.number)),
              ),
          ],
        ),
      ),
    ),
  );
}
