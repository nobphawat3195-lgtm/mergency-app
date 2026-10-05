import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../file_save.dart';
import '../money.dart';
import '../theme.dart';

/// QR พร้อมเพย์พร้อมปุ่ม "บันทึกรูป QR" เลขพร้อมเพย์ปลายทางและปุ่มคัดลอก
///
/// ลูกค้าที่จ่ายจากมือถือเครื่องเดียวกันสแกน QR บนจอตัวเองไม่ได้ จึงต้องบันทึกรูปไว้
/// แล้วเปิดแอปธนาคาร > สแกน > เลือกรูปจากเครื่อง
class PromptPayQrPanel extends StatefulWidget {
  const PromptPayQrPanel({
    super.key,
    required this.qrPayload,
    required this.amount,
    this.promptPayId,
    this.size = 200,
  });

  final String qrPayload;

  /// สตางค์ ใช้ตั้งชื่อไฟล์ fixgo-promptpay-<ยอด>.png
  final int amount;

  /// เบอร์/เลขพร้อมเพย์ปลายทาง (null เมื่อ gateway ไม่เปิดเผย เช่น Stripe)
  final String? promptPayId;
  final double size;

  @override
  State<PromptPayQrPanel> createState() => _PromptPayQrPanelState();
}

class _PromptPayQrPanelState extends State<PromptPayQrPanel> {
  bool _saving = false;

  String get _fileName {
    final baht = widget.amount % 100 == 0
        ? (widget.amount ~/ 100).toString()
        : (widget.amount / 100).toStringAsFixed(2);
    return 'fixgo-promptpay-$baht.png';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await savePngImage(await _renderPng(), _fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'บันทึกรูป QR แล้ว เปิดแอปธนาคาร > สแกน > เลือกรูปจากเครื่อง',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกรูป QR ไม่สำเร็จ ลองแคปหน้าจอแทน')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// วาด QR บนพื้นขาวมีขอบ (quiet zone) ให้แอปธนาคารอ่านรูปจากเครื่องได้แม่น
  Future<Uint8List> _renderPng() async {
    const size = 720.0;
    const margin = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, size, size),
      Paint()..color = Colors.white,
    );
    canvas.translate(margin, margin);
    QrPainter(
      data: widget.qrPayload,
      version: QrVersions.auto,
      gapless: true,
    ).paint(canvas, const Size.square(size - margin * 2));
    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('render failed');
    return data.buffer.asUint8List();
  }

  Future<void> _copyId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('คัดลอกเลขพร้อมเพย์ $id แล้ว')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.promptPayId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(
              data: widget.qrPayload,
              size: widget.size,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: FixGoSpacing.xs),
        Text(
          formatSatang(widget.amount),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: FixGoSpacing.sm),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: const Text('บันทึกรูป QR'),
        ),
        const SizedBox(height: FixGoSpacing.xs),
        Text(
          'จ่ายจากมือถือเครื่องนี้: บันทึกรูป แล้วเปิดแอปธนาคาร > สแกน > เลือกรูปจากเครื่อง',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (id != null && id.isNotEmpty) ...[
          const SizedBox(height: FixGoSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FixGoSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: FixGoColors.accentSoft,
              borderRadius: BorderRadius.circular(FixGoRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'พร้อมเพย์ปลายทาง '),
                        TextSpan(
                          text: id,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'คัดลอกเลขพร้อมเพย์',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () => _copyId(id),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
