import 'package:flutter/material.dart';

import '../category_icons.dart';
import '../theme.dart';

/// โครงหน้าล็อกอินที่ใช้ร่วมกัน 2 แอป: ส่วนหัวไล่สีพร้อมโลโก้ + การ์ดฟอร์มลอยทับ
/// แอปลูกค้าใช้พื้นส้ม แอปช่างใช้พื้นเข้ม ให้แยกออกทันทีว่ากำลังเปิดแอปไหน
class FixGoAuthLayout extends StatelessWidget {
  const FixGoAuthLayout({
    super.key,
    required this.tagline,
    required this.child,
    this.badge,
    this.dark = false,
    this.footer,
  });

  final String tagline;
  final String? badge;
  final bool dark;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final heroColors = dark
        ? const [Color(0xFF2A3242), FixGoColors.navy]
        : const [Color(0xFFFF8A3D), FixGoColors.accent, Color(0xFFE0500C)];

    return Scaffold(
      backgroundColor: FixGoColors.surface,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: heroColors,
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(brandLogoAsset, height: 56),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Text(
                            'FixGo',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: dark
                                    ? FixGoColors.accent
                                    : Colors.white.withValues(alpha: 0.22),
                                borderRadius:
                                    BorderRadius.circular(FixGoRadius.pill),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        tagline,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(FixGoSpacing.lg),
                  decoration: BoxDecoration(
                    color: FixGoColors.background,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x141D2330),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// จุดขาย 3 ข้อใต้ฟอร์มล็อกอิน ให้ผู้ใช้ใหม่มั่นใจก่อนสมัคร
class FixGoTrustRow extends StatelessWidget {
  const FixGoTrustRow({super.key, required this.items});

  final List<({IconData icon, String label})> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: const BoxDecoration(
                    color: FixGoColors.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.icon, size: 20, color: FixGoColors.accent),
                ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: FixGoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
