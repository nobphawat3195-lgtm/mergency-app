import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../theme.dart';

/// หน้าเว็บที่ backend ให้บริการที่ /api/legal/<slug>
abstract final class LegalPages {
  static const privacy = 'privacy';
  static const terms = 'terms';
  static const deleteAccount = 'delete-account';
  static const support = 'support';
}

Future<void> openLegalPage(
  BuildContext context,
  FixGoApiClient api,
  String page,
) async {
  final url = api.legalPageUrl(page);
  final messenger = ScaffoldMessenger.of(context);
  final opened = await launchUrl(url, mode: LaunchMode.inAppBrowserView)
      .catchError((_) => false);
  if (!opened) {
    messenger.showSnackBar(SnackBar(content: Text('เปิดหน้าไม่สำเร็จ: $url')));
  }
}

/// ข้อความใต้ฟอร์มล็อกอิน: การเข้าสู่ระบบถือว่ายอมรับข้อตกลงและนโยบาย
class LegalConsentText extends StatelessWidget {
  const LegalConsentText({super.key, required this.api});

  final FixGoApiClient api;

  @override
  Widget build(BuildContext context) {
    Widget link(String label, String page) => InkWell(
          onTap: () => openLegalPage(context, api, page),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FixGoColors.accent,
                decoration: TextDecoration.underline,
                decorationColor: FixGoColors.accent,
              ),
            ),
          ),
        );
    const muted = TextStyle(fontSize: 13, color: FixGoColors.textSecondary);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        const Text('การเข้าสู่ระบบถือว่าคุณยอมรับ', style: muted),
        link('ข้อตกลงการใช้งาน', LegalPages.terms),
        const Text('และ', style: muted),
        link('นโยบายความเป็นส่วนตัว', LegalPages.privacy),
      ],
    );
  }
}

/// เมนูในหน้าโปรไฟล์: ติดต่อ นโยบาย ข้อตกลง และลบบัญชี (App Store กำหนดให้มีในแอป)
class AccountSettingsTiles extends StatelessWidget {
  const AccountSettingsTiles({
    super.key,
    required this.api,
    required this.onDeleted,
  });

  final FixGoApiClient api;

  /// เรียกหลังลบสำเร็จ ให้แอปล้างโทเคนและกลับหน้าล็อกอิน
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.support_agent_outlined),
          title: const Text('ติดต่อฝ่ายช่วยเหลือ'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => openLegalPage(context, api, LegalPages.support),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('นโยบายความเป็นส่วนตัว'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => openLegalPage(context, api, LegalPages.privacy),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('ข้อตกลงการใช้งาน'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => openLegalPage(context, api, LegalPages.terms),
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined,
              color: FixGoColors.error),
          title: const Text(
            'ลบบัญชี',
            style: TextStyle(color: FixGoColors.error),
          ),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) =>
                _DeleteAccountDialog(api: api, onDeleted: onDeleted),
          ),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.api, required this.onDeleted});

  final FixGoApiClient api;
  final VoidCallback onDeleted;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.api.deleteAccount();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      widget.onDeleted();
      messenger.showSnackBar(
        const SnackBar(content: Text('ลบบัญชีเรียบร้อยแล้ว')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ลบบัญชีถาวร'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'เบอร์โทร ชื่อ ที่อยู่ รูป และข้อมูลรับเงินจะถูกลบทันที '
            'และกู้คืนไม่ได้ ตัวเลขธุรกรรมจะเก็บไว้ตามกฎหมายบัญชีโดยไม่ระบุตัวตน',
          ),
          const SizedBox(height: FixGoSpacing.sm),
          const Text(
            'ต้องไม่มีงานที่กำลังดำเนินการหรือยอดที่ยังค้างก่อนลบ',
            style: TextStyle(fontSize: 13, color: FixGoColors.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: FixGoSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(
                color: FixGoColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        TextButton(
          onPressed: _deleting ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: FixGoColors.error),
          child: _deleting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ลบบัญชีถาวร'),
        ),
      ],
    );
  }
}
