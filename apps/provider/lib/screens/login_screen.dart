import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/foundation.dart';
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

  /// ปุ่ม LINE แสดงทั้งเว็บและแอปมือถือ เมื่อเซิร์ฟเวอร์ตั้งค่า LINE Login ของแอปช่างแล้ว
  Future<bool>? _lineEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lineEnabled != null) return;
    final appState = ProviderAppScope.of(context);
    _lineEnabled = appState.api
        .isLineLoginEnabled(role: ApiRole.provider)
        .catchError((_) => false);
    if (appState.lineLoginFailed) {
      appState.lineLoginFailed = false;
      // มักเกิดบน iPhone เมื่อเปิดลิงก์ในเบราว์เซอร์ของแอป LINE แล้วเด้งไปอีกเบราว์เซอร์
      _error = lineLoginFailedMessage;
    }
  }

  Future<void> _loginWithLine() async {
    if (!kIsWeb) return _loginWithLineNative();
    final uri =
        ProviderAppScope.of(context).api.lineLoginStartUriFor(ApiRole.provider);
    setState(() => _loading = true);
    if (!await openLineLoginPage(uri) && mounted) {
      setState(() {
        _loading = false;
        _error = 'เปิดหน้า LINE ไม่สำเร็จ';
      });
    }
  }

  /// iOS/Android: เปิดหน้า LINE ในหน้าต่างของระบบ แล้วรับตั๋วกลับทาง fixgofixer://auth/line
  Future<void> _loginWithLineNative() async {
    final appState = ProviderAppScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await runNativeLineLogin(
      startUri: appState.api.nativeLineLoginStartUriFor(ApiRole.provider),
      callbackScheme: 'fixgofixer',
    );
    if (!mounted) return;
    try {
      switch (result) {
        case NativeLineTicket(:final ticket):
          final session =
              await appState.api.exchangeLineTicketSession(ticket);
          appState.signIn(session.accessToken, hasProfile: session.hasProfile);
          return;
        case NativeLineCancelled():
          break;
        case NativeLineFailed():
          setState(() => _error = lineLoginFailedMessage);
      }
    } on ApiException catch (_) {
      if (mounted) setState(() => _error = lineLoginFailedMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
    return FixGoAuthLayout(
      dark: true,
      badge: 'Fixer',
      tagline: 'รับงานซ่อมรถใกล้คุณ\nเงินเข้ากระเป๋าเมื่อยืนยันการชำระแล้ว',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_otpSent)
            FutureBuilder<bool>(
              future: _lineEnabled,
              builder: (context, snapshot) {
                if (snapshot.data != true) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ช่างใหม่สมัครด้วย LINE ได้เลย ไม่ต้องรอ SMS',
                      style: TextStyle(color: FixGoColors.textSecondary),
                    ),
                    const SizedBox(height: FixGoSpacing.sm),
                    LineLoginButton(
                      onPressed: _loading ? null : _loginWithLine,
                    ),
                    const SizedBox(height: FixGoSpacing.md),
                    const LoginOrDivider(),
                    const SizedBox(height: FixGoSpacing.md),
                  ],
                );
              },
            ),
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
          if (_otpSent) ...[
            const SizedBox(height: FixGoSpacing.sm),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _otpSent = false;
                        _error = null;
                        _codeController.clear();
                      }),
              child: const Text('เปลี่ยนเบอร์โทร'),
            ),
          ],
          const SizedBox(height: FixGoSpacing.md),
          LegalConsentText(api: ProviderAppScope.of(context).api),
        ],
      ),
    );
  }
}
