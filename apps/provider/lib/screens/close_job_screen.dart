import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';

const _maxCarPhotos = 5;
const _maxReceipts = 3;

/// ปิดงาน: แนบรูปรถหลังซ่อมเสร็จ 1-5 รูป (บังคับ) และใบเสร็จ/สลิปไม่เกิน 3 รูป (ไม่บังคับ)
/// ลูกค้าเห็นรูปเหล่านี้ในหน้าติดตามงานและประวัติ คืน true เมื่อปิดงานสำเร็จ
///
/// เลือกจากคลังรูปตามกฎแอปช่าง (ถ่ายด้วยกล้องของเครื่องก่อน แล้วแนบจากคลังรูป)
class CloseJobScreen extends StatefulWidget {
  const CloseJobScreen({super.key, required this.order});

  final Order order;

  @override
  State<CloseJobScreen> createState() => _CloseJobScreenState();
}

class _CloseJobScreenState extends State<CloseJobScreen> {
  final _carPhotos = <String>[];
  final _receipts = <String>[];
  bool _uploading = false;
  bool _submitting = false;
  String? _error;

  String _contentTypeFor(XFile file) {
    final name = file.name.toLowerCase();
    if (file.mimeType == 'image/png' || name.endsWith('.png')) {
      return 'image/png';
    }
    if (file.mimeType == 'image/webp' || name.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  Future<void> _add(List<String> target, int max) async {
    final remaining = max - target.length;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      maxWidth: 1920,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final api = ProviderAppScope.of(context).api;
      for (final file in picked.take(remaining)) {
        final url = await api.uploadImage(
          bytes: await file.readAsBytes(),
          fileName: file.name,
          contentType: _contentTypeFor(file),
          scope: 'ORDER',
        );
        if (!mounted) return;
        setState(() => target.add(url));
      }
      if (picked.length > remaining && mounted) {
        setState(
            () => _error = 'แนบได้สูงสุด $max รูป ระบบใช้ $remaining รูปแรก');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } catch (_) {
      if (mounted) setState(() => _error = 'อ่านหรืออัปโหลดรูปไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_carPhotos.isEmpty) {
      setState(() => _error = 'กรุณาแนบรูปรถหลังซ่อมเสร็จอย่างน้อย 1 รูป');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ProviderAppScope.of(context).api.completeJob(
            widget.order.id,
            carPhotoUrls: _carPhotos,
            receiptPhotoUrls: _receipts,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ปิดงานเรียบร้อย ส่งรูปให้ลูกค้าแล้ว')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = userMessageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final busy = _uploading || _submitting;
    return Scaffold(
      appBar: AppBar(title: const Text('ปิดงาน')),
      body: ListView(
        padding: const EdgeInsets.all(FixGoSpacing.md),
        children: [
          Text(
            'ราคาที่ลูกค้ายืนยันแล้ว '
            '${formatSatang(order.priceProposed ?? order.priceEstimated)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: FixGoSpacing.xs),
          Text(
            'ลูกค้าจะเห็นรูปเหล่านี้ในหน้าติดตามงานและประวัติงาน',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: FixGoSpacing.lg),
          _PhotoSection(
            title: 'รูปรถหลังซ่อมเสร็จ (บังคับ 1-$_maxCarPhotos รูป)',
            hint: 'ถ่ายด้วยกล้องของเครื่องก่อน แล้วกดแนบจากคลังรูป',
            urls: _carPhotos,
            max: _maxCarPhotos,
            busy: busy,
            onAdd: () => _add(_carPhotos, _maxCarPhotos),
            onRemove: (index) => setState(() => _carPhotos.removeAt(index)),
          ),
          const SizedBox(height: FixGoSpacing.lg),
          _PhotoSection(
            title: 'ใบเสร็จ / สลิป (ไม่บังคับ สูงสุด $_maxReceipts รูป)',
            hint: 'เช่น ใบเสร็จค่าอะไหล่ ให้ลูกค้าเก็บไว้เป็นหลักฐาน',
            urls: _receipts,
            max: _maxReceipts,
            busy: busy,
            onAdd: () => _add(_receipts, _maxReceipts),
            onRemove: (index) => setState(() => _receipts.removeAt(index)),
          ),
          if (_uploading) ...[
            const SizedBox(height: FixGoSpacing.md),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: FixGoSpacing.md),
            Text(_error!, style: const TextStyle(color: FixGoColors.error)),
          ],
          const SizedBox(height: FixGoSpacing.lg),
          FixGoButton(
            label: _submitting ? 'กำลังปิดงาน...' : 'ยืนยันปิดงาน',
            icon: Icons.check_circle_outline,
            onPressed: busy || _carPhotos.isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.title,
    required this.hint,
    required this.urls,
    required this.max,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String hint;
  final List<String> urls;
  final int max;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(hint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: FixGoSpacing.sm),
        if (urls.isNotEmpty) ...[
          PhotoStrip(urls: urls, size: 88, onRemove: busy ? null : onRemove),
          const SizedBox(height: FixGoSpacing.sm),
        ],
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: busy || urls.length >= max ? null : onAdd,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text('แนบรูป (${urls.length}/$max)'),
        ),
      ],
    );
  }
}
