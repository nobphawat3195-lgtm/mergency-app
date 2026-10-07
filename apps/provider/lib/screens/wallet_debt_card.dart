import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// ค่าบริการแพลตฟอร์มที่ค้างจากงานเงินสด พร้อมปุ่มโอนชำระด้วยพร้อมเพย์
/// ค้างเกินเพดานแล้วเปิดรับงานไม่ได้จนกว่าทีมงานยืนยันยอดโอนคืน
class WalletDebtCard extends StatelessWidget {
  const WalletDebtCard({
    super.key,
    required this.debt,
    required this.api,
    required this.onChanged,
  });

  final WalletDebt debt;
  final FixGoApiClient api;

  /// เรียกหลังส่งสลิปสำเร็จ ให้หน้าที่แสดงอยู่โหลดข้อมูลใหม่
  final VoidCallback onChanged;

  Future<void> _pay(BuildContext context) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => _SettlementDialog(api: api),
    );
    if (submitted == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final color = debt.blocked ? FixGoColors.error : FixGoColors.warning;
    return Container(
      padding: const EdgeInsets.all(FixGoSpacing.md),
      decoration: BoxDecoration(
        color: FixGoColors.background,
        borderRadius: BorderRadius.circular(FixGoRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: fixGoCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(uiIconBanknote, width: 32, height: 32),
              const SizedBox(width: FixGoSpacing.sm),
              Expanded(
                child: Text(
                  debt.blocked
                      ? 'ปิดรับงานชั่วคราว: ค้างค่าบริการเกินเพดาน'
                      : 'ค่าบริการแพลตฟอร์มที่ค้าง',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FixGoSpacing.sm),
          Text(
            formatSatang(debt.owed),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: FixGoColors.navy,
            ),
          ),
          Text(
            'จากงานที่ลูกค้าจ่ายเงินสดให้คุณ · เพดาน ${formatSatang(debt.limit)} '
            '${debt.blocked ? '' : '(ยังรับงานได้ตามปกติ)'}',
            style: const TextStyle(
              fontSize: 13,
              color: FixGoColors.textSecondary,
            ),
          ),
          if (debt.blocked) ...[
            const SizedBox(height: FixGoSpacing.sm),
            const Text(
              'โอนชำระยอดนี้ แล้วรอทีมงานยืนยัน ก็เปิดรับงานต่อได้ทันที',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
          if (debt.lastRejectReason != null && !debt.hasPendingSlip) ...[
            const SizedBox(height: FixGoSpacing.sm),
            Text(
              'สลิปครั้งก่อนไม่ผ่าน: ${debt.lastRejectReason}',
              style: const TextStyle(color: FixGoColors.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: FixGoSpacing.md),
          if (debt.hasPendingSlip)
            Row(
              children: [
                const Icon(Icons.hourglass_top_rounded,
                    size: 18, color: FixGoColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ส่งสลิป ${formatSatang(debt.pendingAmount!)} แล้ว '
                    'รอทีมงานตรวจยอดเข้าบัญชี',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          else
            FixGoButton(
              label: 'โอนชำระด้วยพร้อมเพย์',
              icon: Icons.qr_code_2_rounded,
              onPressed: () => _pay(context),
            ),
        ],
      ),
    );
  }
}

class _SettlementDialog extends StatefulWidget {
  const _SettlementDialog({required this.api});

  final FixGoApiClient api;

  @override
  State<_SettlementDialog> createState() => _SettlementDialogState();
}

class _SettlementDialogState extends State<_SettlementDialog> {
  late Future<
      ({
        int amount,
        String qrPayload,
        String? payeeName,
        String? promptPayId,
      })> _qr = widget.api.getSettlementQr();
  bool _uploading = false;
  String? _error;

  Future<void> _attachSlip() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final url = await widget.api.uploadImage(
        bytes: bytes,
        fileName: file.name,
        contentType: name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg',
        scope: 'PAYMENT_SLIP',
      );
      await widget.api.submitSettlementSlip(url);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = userMessageFor(error));
    } catch (_) {
      if (mounted) setState(() => _error = 'อัปโหลดสลิปไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('โอนชำระค่าบริการ'),
      content: SingleChildScrollView(
        child: FutureBuilder(
          future: _qr,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorStateView(
                compact: true,
                error: snapshot.error,
                title: 'โหลด QR ไม่สำเร็จ',
                onRetry: () => setState(() => _qr = widget.api.getSettlementQr()),
              );
            }
            final qr = snapshot.data;
            if (qr == null) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PromptPayQrPanel(
                  qrPayload: qr.qrPayload,
                  amount: qr.amount,
                  promptPayId: qr.promptPayId,
                ),
                if (qr.payeeName != null)
                  Text(
                    'โอนเข้าบัญชี: ${qr.payeeName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: FixGoSpacing.sm),
                const Text(
                  'สแกนด้วยแอปธนาคาร โอนแล้วกดแนบสลิป '
                  'ทีมงานตรวจยอดเข้าบัญชีแล้วจะแจ้งให้ทราบ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: FixGoColors.textSecondary,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: FixGoSpacing.sm),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: FixGoColors.error),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(false),
          child: const Text('ปิด'),
        ),
        FilledButton.icon(
          onPressed: _uploading ? null : _attachSlip,
          icon: _uploading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.receipt_long_outlined),
          label: const Text('แนบสลิป'),
        ),
      ],
    );
  }
}
