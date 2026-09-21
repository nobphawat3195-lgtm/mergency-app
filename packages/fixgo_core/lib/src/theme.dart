import 'package:flutter/material.dart';

/// Design tokens ของ MechNow: น้ำเงินเข้มสร้างความน่าเชื่อถือ และส้มใช้กับการกระทำ
/// ที่ต้องเห็นได้ทันทีในสถานการณ์ฉุกเฉิน เป็นภาพจำของแบรนด์เองไม่อิงแบรนด์รถใด
abstract final class FixGoColors {
  static const navy = Color(0xFF0B1F3A);
  static const brandBlue = Color(0xFF2563EB);
  static const accent = Color(0xFFFF6B35);
  static const accentActive = Color(0xFFE84F1C);
  static const background = Color(0xFFF8FAFC);
  static const surface = Color(0xFFF1F5F9);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const success = Color(0xFF16A36A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFDC3545);
  static const hairline = Color(0xFFE2E8F0);
}

// ฟอนต์ประกาศอยู่ใน package fixgo_core เอง แต่ web build (CanvasKit) ต้องการชื่อ
// แบบเต็มมี prefix "packages/<pkg>/" เสมอ — ใส่ให้ครบทุกจุดที่สร้าง TextStyle เอง
// (ButtonStyle.textStyle ไม่ inherit fontFamily จาก ThemeData.fontFamily ให้อัตโนมัติ
// ต่างจาก TextTheme ทั่วไป ถ้าลืมใส่ ตัวหนังสือบนปุ่มจะหายไปเงียบๆ บน web)
const fixGoFontFamily = 'packages/fixgo_core/NotoSansThai';

abstract final class FixGoSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

ThemeData buildFixGoTheme() {
  const colorScheme = ColorScheme.light(
    primary: FixGoColors.accent,
    onPrimary: Colors.white,
    secondary: FixGoColors.brandBlue,
    onSecondary: Colors.white,
    surface: FixGoColors.background,
    onSurface: FixGoColors.textPrimary,
    error: FixGoColors.error,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: FixGoColors.background,
    // ฟอนต์ประกาศอยู่ใน package fixgo_core เอง แต่ web build (CanvasKit) ต้องการชื่อ
    // แบบเต็มมี prefix "packages/<pkg>/" เสมอ ไม่งั้นจะ fallback ไปหาฟอนต์จากอินเทอร์เน็ต
    fontFamily: fixGoFontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: FixGoColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: fixGoFontFamily,
        color: FixGoColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      shadowColor: FixGoColors.navy.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: FixGoColors.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: FixGoColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFD6D6D6),
        disabledForegroundColor: FixGoColors.textSecondary,
        minimumSize: const Size.fromHeight(56),
        elevation: 1,
        shadowColor: FixGoColors.accent.withValues(alpha: 0.28),
        textStyle: const TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FixGoColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FixGoColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FixGoColors.brandBlue, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: FixGoColors.accent.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 12,
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? FixGoColors.navy
              : FixGoColors.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? FixGoColors.accent
              : FixGoColors.textSecondary,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontFamily: fixGoFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: FixGoColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: fixGoFontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: FixGoColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: fixGoFontFamily,
        fontSize: 15,
        height: 1.5,
        color: FixGoColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontFamily: fixGoFontFamily,
        fontSize: 13,
        height: 1.4,
        color: FixGoColors.textSecondary,
      ),
    ),
  );
}
