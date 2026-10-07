import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';

/// มีบัญชีรับเงินพอให้เบิกได้หรือยัง (ตรงกับเงื่อนไขของ backend)
bool hasPayoutInfo(Map<String, dynamic> profile) {
  bool filled(String key) =>
      (profile[key] as String?)?.trim().isNotEmpty ?? false;
  return filled('promptPayId') ||
      (filled('bankName') &&
          filled('bankAccountName') &&
          filled('bankAccountNumber'));
}

/// เปิดฟอร์มข้อมูลรับเงิน คืน true เมื่อบันทึกสำเร็จ
///
/// บันทึกไม่ผ่านจะแสดงข้อความในฟอร์ม ไม่ปิดหน้าต่างและไม่ล้างข้อมูลที่พิมพ์ไว้
Future<bool> showPayoutInfoForm(
  BuildContext context, {
  required FixGoApiClient api,
  Map<String, dynamic>? profile,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PayoutInfoDialog(api: api, profile: profile ?? const {}),
  );
  return saved == true;
}

class _PayoutInfoDialog extends StatefulWidget {
  const _PayoutInfoDialog({required this.api, required this.profile});

  final FixGoApiClient api;
  final Map<String, dynamic> profile;

  @override
  State<_PayoutInfoDialog> createState() => _PayoutInfoDialogState();
}

class _PayoutInfoDialogState extends State<_PayoutInfoDialog> {
  late final _bankName = _controller('bankName');
  late final _accountName = _controller('bankAccountName');
  late final _accountNumber = _controller('bankAccountNumber');
  late final _promptPay = _controller('promptPayId');
  bool _saving = false;
  String? _error;

  TextEditingController _controller(String key) =>
      TextEditingController(text: widget.profile[key] as String? ?? '');

  @override
  void dispose() {
    _bankName.dispose();
    _accountName.dispose();
    _accountNumber.dispose();
    _promptPay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bank = [
      _bankName,
      _accountName,
      _accountNumber,
    ].map((controller) => controller.text.trim()).toList();
    final promptPay = _promptPay.text.trim();
    final bankComplete = bank.every((value) => value.isNotEmpty);
    final bankStarted = bank.any((value) => value.isNotEmpty);
    if (!bankComplete && promptPay.isEmpty) {
      setState(() {
        _error = bankStarted
            ? 'กรอกบัญชีธนาคารให้ครบทั้ง 3 ช่อง หรือกรอกพร้อมเพย์แทน'
            : 'กรอกบัญชีธนาคาร (ธนาคาร ชื่อบัญชี เลขบัญชี) หรือพร้อมเพย์ อย่างใดอย่างหนึ่ง';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updatePayoutInfo(
        bankName: _bankName.text,
        bankAccountName: _accountName.text,
        bankAccountNumber: _accountNumber.text,
        promptPayId: promptPay,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userMessageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ข้อมูลรับเงิน'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'กรอกบัญชีธนาคารให้ครบ 3 ช่อง หรือกรอกแค่พร้อมเพย์ก็ได้',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: _bankName,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'ธนาคาร'),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: _accountName,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'ชื่อบัญชี'),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: _accountNumber,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'เลขบัญชี'),
            ),
            const SizedBox(height: FixGoSpacing.sm),
            TextField(
              controller: _promptPay,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'พร้อมเพย์ (เบอร์โทรหรือเลขบัตรประชาชน)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: FixGoSpacing.sm),
              Text(_error!, style: const TextStyle(color: FixGoColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'กำลังบันทึก...' : 'บันทึก'),
        ),
      ],
    );
  }
}
