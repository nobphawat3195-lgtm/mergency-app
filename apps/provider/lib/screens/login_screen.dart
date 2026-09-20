import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';

class ProviderLoginScreen extends StatefulWidget {
  const ProviderLoginScreen({super.key});

  @override
  State<ProviderLoginScreen> createState() => _ProviderLoginScreenState();
}

class _ProviderLoginScreenState extends State<ProviderLoginScreen> {
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
      final api = ProviderAppScope.of(context).api;
      final devCode = await api.requestOtp(
        _phoneController.text.trim(),
        ApiRole.provider,
      );
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        if (devCode != null) _codeController.text = devCode;
      });
    });
  }

  Future<void> _verifyOtp() {
    return _run(() async {
      final appState = ProviderAppScope.of(context);
      final result = await appState.api.verifyOtp(
        _phoneController.text.trim(),
        ApiRole.provider,
        _codeController.text.trim(),
      );
      appState.signIn(result.accessToken, hasProfile: result.hasProfile);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixGoColors.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FixGoSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: FixGoSpacing.xl),
              Row(
                children: [
                  const Text(
                    'FixGo',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: FixGoSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FixGoSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: FixGoColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'FIXER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FixGoSpacing.sm),
              const Text(
                'รับงานซ่อมรถใกล้คุณ\nรับเงินเข้ากระเป๋าทันทีที่งานจบ',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: FixGoSpacing.xl),
              Container(
                padding: const EdgeInsets.all(FixGoSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _otpSent ? 'ใส่รหัส OTP' : 'เข้าสู่ระบบสำหรับช่าง',
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
                        hintText: 'เบอร์โทรศัพท์',
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
