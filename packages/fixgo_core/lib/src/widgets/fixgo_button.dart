import 'package:flutter/material.dart';

import '../theme.dart';

/// ปุ่มหลักของแอป — สีเหลืองเสมอ ห้ามมีปุ่มสีอื่นแข่งความสนใจในหน้าเดียวกัน
class FixGoButton extends StatelessWidget {
  const FixGoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: FixGoSpacing.sm),
                ],
                Text(label),
              ],
            ),
    );
  }
}

/// ปุ่มรองแบบขอบบาง ใช้กับการกระทำที่ไม่ใช่ทางหลัก เช่น ปฏิเสธงาน
class FixGoSecondaryButton extends StatelessWidget {
  const FixGoSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    // BMW button-secondary: ตัวหนังสือ/ขอบสี ink (ดำเข้ม) พื้นขาว มุมเหลี่ยมคม
    final color = destructive ? FixGoColors.error : FixGoColors.textPrimary;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size.fromHeight(56),
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(label),
    );
  }
}
