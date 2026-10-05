import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// ข้อความเมื่อล็อกอิน LINE ไม่สำเร็จ ใช้ทั้งเว็บและแอปมือถือ
const lineLoginFailedMessage =
    'เข้าสู่ระบบด้วย LINE ไม่สำเร็จ ลองใหม่อีกครั้ง หรือเปิดลิงก์นี้ใน Safari/Chrome';

/// เปิดหน้า LINE Login ในแท็บเดิม (เว็บ) LINE จะพากลับมาพร้อม ?line_ticket=
Future<bool> openLineLoginPage(Uri uri) =>
    launchUrl(uri, webOnlyWindowName: '_self');

/// ผลล็อกอิน LINE บนแอปมือถือ: ได้ตั๋ว / ผู้ใช้ปิดหน้าต่างเอง / ไม่สำเร็จ
sealed class NativeLineLoginResult {
  const NativeLineLoginResult();
}

class NativeLineTicket extends NativeLineLoginResult {
  const NativeLineTicket(this.ticket);
  final String ticket;
}

class NativeLineCancelled extends NativeLineLoginResult {
  const NativeLineCancelled();
}

class NativeLineFailed extends NativeLineLoginResult {
  const NativeLineFailed();
}

/// แอปมือถือ: เปิดหน้า LINE ใน ASWebAuthenticationSession (iOS) หรือ Custom Tabs (Android)
/// รอ backend พากลับ `<callbackScheme>://auth/line?line_ticket=...` แล้วคืนตั๋วไปแลกโทเคน
Future<NativeLineLoginResult> runNativeLineLogin({
  required Uri startUri,
  required String callbackScheme,
}) async {
  try {
    final result = await FlutterWebAuth2.authenticate(
      url: startUri.toString(),
      callbackUrlScheme: callbackScheme,
    );
    final query = Uri.parse(result).queryParameters;
    final ticket = query['line_ticket'];
    if (ticket == null || ticket.isEmpty) return const NativeLineFailed();
    return NativeLineTicket(ticket);
  } on PlatformException catch (error) {
    return error.code == 'CANCELED'
        ? const NativeLineCancelled()
        : const NativeLineFailed();
  } catch (_) {
    return const NativeLineFailed();
  }
}

/// ปุ่มตามแนวทางแบรนด์ LINE: พื้นเขียว LINE ตัวอักษรขาว
class LineLoginButton extends StatelessWidget {
  const LineLoginButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.chat_bubble_rounded, size: 22),
      label: const Text(
        'เข้าสู่ระบบด้วย LINE',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: const Color(0xFF06C755),
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
      ),
    );
  }
}

/// เส้นคั่นระหว่างปุ่ม LINE กับช่องเบอร์โทร
class LoginOrDivider extends StatelessWidget {
  const LoginOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: FixGoSpacing.sm),
          child: Text(
            'หรือใช้เบอร์โทร',
            style: TextStyle(color: FixGoColors.textSecondary),
          ),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}
