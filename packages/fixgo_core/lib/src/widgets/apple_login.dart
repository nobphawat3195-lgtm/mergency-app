import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// ข้อความเมื่อเข้าสู่ระบบด้วย Apple ไม่สำเร็จ
const appleLoginFailedMessage =
    'เข้าสู่ระบบด้วย Apple ไม่สำเร็จ ลองใหม่อีกครั้ง หรือใช้เบอร์โทรแทน';

/// แสดงปุ่ม Apple เฉพาะแอป iPhone (App Store Guideline 4.8 เมื่อมีปุ่ม LINE)
/// เว็บและ Android ไม่แสดง
bool get showAppleLogin =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// ผลจากหน้าต่าง Sign in with Apple ของระบบ
sealed class AppleLoginResult {
  const AppleLoginResult();
}

class AppleCredential extends AppleLoginResult {
  const AppleCredential({
    required this.identityToken,
    required this.nonce,
    this.authorizationCode,
    this.fullName,
  });

  final String identityToken;

  /// nonce ดิบ: Apple ได้ sha256 ของค่านี้ backend ตรวจว่าตรงกัน
  final String nonce;
  final String? authorizationCode;

  /// Apple ส่งชื่อให้เฉพาะครั้งแรกที่ผู้ใช้กดยอมรับ
  final String? fullName;
}

class AppleLoginCancelled extends AppleLoginResult {
  const AppleLoginCancelled();
}

class AppleLoginFailed extends AppleLoginResult {
  const AppleLoginFailed();
}

String _randomNonce([int length = 32]) {
  const chars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(length, (_) => chars[random.nextInt(chars.length)])
      .join();
}

/// เปิดหน้าต่าง Sign in with Apple ขอชื่อ (ไม่ขออีเมล: ระบบไม่ใช้)
Future<AppleLoginResult> runAppleLogin() async {
  final nonce = _randomNonce();
  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.fullName],
      nonce: sha256.convert(utf8.encode(nonce)).toString(),
    );
    final token = credential.identityToken;
    if (token == null || token.isEmpty) return const AppleLoginFailed();
    final name = [credential.givenName, credential.familyName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    return AppleCredential(
      identityToken: token,
      nonce: nonce,
      authorizationCode: credential.authorizationCode.isEmpty
          ? null
          : credential.authorizationCode,
      fullName: name.isEmpty ? null : name,
    );
  } on SignInWithAppleAuthorizationException catch (error) {
    return error.code == AuthorizationErrorCode.canceled
        ? const AppleLoginCancelled()
        : const AppleLoginFailed();
  } catch (_) {
    return const AppleLoginFailed();
  }
}

/// ปุ่มตามแนวทางของ Apple (Human Interface Guidelines): พื้นดำบนแผ่นฟอร์มสีอ่อน ขนาดเท่าปุ่ม LINE
class AppleLoginButton extends StatelessWidget {
  const AppleLoginButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // ปุ่มของแพ็กเกจไม่มีสถานะปิด: ระหว่างกำลังล็อกอินให้จางและกดไม่ได้
    final enabled = onPressed != null;
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: SignInWithAppleButton(
          onPressed: onPressed ?? () {},
          text: 'ดำเนินการต่อด้วย Apple',
          height: 54,
          borderRadius: const BorderRadius.all(Radius.circular(27)),
        ),
      ),
    );
  }
}
