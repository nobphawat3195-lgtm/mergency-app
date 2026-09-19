import 'package:flutter/material.dart';

/// สีแบรนด์ FixGo — อิงจาก BMW corporate design system เต็มรูปแบบ
/// (น้ำเงิน BMW #1c69d4 + พื้นขาว/ครีม + มุมเหลี่ยมคมทั้งหมด ไม่มีมุมมนเลย)
/// ชื่อตัวแปร `navy`/`accent` เก็บไว้ตามเดิมเพื่อไม่ต้องแก้ทุกไฟล์ที่อ้างอิง
/// แต่ตอนนี้ `navy` คือพื้นหลังเข้ม (BMW surface-dark) และ `accent` คือ
/// น้ำเงินหลักของ BMW (ใช้กับปุ่ม action ทุกจุด)
abstract final class FixGoColors {
  static const navy = Color(0xFF1A2129);
  static const accent = Color(0xFF1C69D4);
  static const accentActive = Color(0xFF0653B6);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7F7F7);
  static const textPrimary = Color(0xFF262626);
  static const textSecondary = Color(0xFF6B6B6B);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFDC2626);
  static const hairline = Color(0xFFE6E6E6);
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
    primary: FixGoColors.navy,
    onPrimary: Colors.white,
    secondary: FixGoColors.accent,
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
      backgroundColor: FixGoColors.background,
      foregroundColor: FixGoColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: fixGoFontFamily,
        color: FixGoColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    // BMW ใช้มุมเหลี่ยมคมทุกจุด (rounded.none) ไม่มีมุมมนเลยทั้งระบบ
    cardTheme: const CardThemeData(
      color: FixGoColors.background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: FixGoColors.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    // ปุ่ม action ใช้สีน้ำเงิน BMW อย่างเดียวทั้งแอป ผู้ใช้จะไม่สับสนว่าต้องกดอะไรต่อ
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: FixGoColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFD6D6D6),
        disabledForegroundColor: FixGoColors.textSecondary,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        textStyle: const TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        shape: const RoundedRectangleBorder(),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: FixGoColors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: FixGoColors.accent, width: 1.5),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontFamily: fixGoFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: FixGoColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: fixGoFontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w700,
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
