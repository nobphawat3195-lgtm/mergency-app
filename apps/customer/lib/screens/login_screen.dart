import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _otpSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestOtp() {
    return _run(() async {
      final api = AppStateScope.of(context).api;
      final devCode = await api.requestOtp(
        _phoneController.text.trim(),
        ApiRole.customer,
      );
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        // backend โหมด development ส่งรหัสกลับมาให้เลย จะได้ทดสอบโดยไม่ต้องต่อ SMS
        if (devCode != null) _codeController.text = devCode;
      });
    });
  }

  Future<void> _verifyOtp() {
    return _run(() async {
      final appState = AppStateScope.of(context);
      final result = await appState.api.verifyOtp(
        _phoneController.text.trim(),
        ApiRole.customer,
        _codeController.text.trim(),
      );
      appState.signIn(result.accessToken);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FixGoAuthLayout(
      tagline: 'รถเสีย ไม่ต้องรอ\nเรียกช่างใกล้คุณได้ 24 ชม.',
      footer: const FixGoTrustRow(
        items: [
          (icon: Icons.near_me_outlined, label: 'ช่างใกล้คุณ\nไปถึงไว'),
          (icon: Icons.receipt_long_outlined, label: 'รู้ราคา\nก่อนซ่อม'),
          (icon: Icons.verified_user_outlined, label: 'ช่างผ่าน\nการตรวจสอบ'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _otpSent ? 'ใส่รหัส OTP' : 'เข้าสู่ระบบด้วยเบอร์โทร',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FixGoSpacing.md),
          TextField(
            controller: _phoneController,
            enabled: !_otpSent,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              hintText: 'เบอร์โทรศัพท์ เช่น 0812345678',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_otpSent) ...[
            const SizedBox(height: FixGoSpacing.md),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                hintText: 'รหัส 6 หลัก',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: FixGoSpacing.md),
            Text(
              _error!,
              style: const TextStyle(color: FixGoColors.error),
            ),
          ],
          const SizedBox(height: FixGoSpacing.lg),
          FixGoButton(
            label: _otpSent ? 'ยืนยันรหัส' : 'ขอรหัส OTP',
            loading: _loading,
            onPressed: _otpSent ? _verifyOtp : _requestOtp,
          ),
          if (_otpSent) ...[
            const SizedBox(height: FixGoSpacing.sm),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _otpSent = false;
                        _codeController.clear();
                      }),
              child: const Text('เปลี่ยนเบอร์โทร'),
            ),
          ],
        ],
      ),
    );
  }
}
