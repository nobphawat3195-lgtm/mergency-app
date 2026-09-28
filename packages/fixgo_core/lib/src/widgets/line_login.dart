import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// เปิดหน้า LINE Login ในแท็บเดิม (เว็บ) LINE จะพากลับมาพร้อม ?line_ticket=
Future<bool> openLineLoginPage(Uri uri) =>
    launchUrl(uri, webOnlyWindowName: '_self');

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
