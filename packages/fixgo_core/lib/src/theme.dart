import 'package:flutter/material.dart';

/// สีแบรนด์ FixGo — โทนสว่าง ส้มเป็นสีหลัก (สื่อความเร่งด่วน/ความช่วยเหลือ)
/// ตัดกับพื้นเทาอ่อน + การ์ดขาวมุมโค้ง อ่านง่ายทั้งกลางแดดและตอนกลางคืน
///
/// ชื่อ `navy`/`accent` เก็บไว้ตามเดิมเพื่อไม่ต้องแก้ทุกไฟล์ที่อ้างอิง
/// - `navy`   = สีหมึกเข้ม ใช้กับหัวข้อ ตัวเลขราคา และการ์ดพื้นเข้ม
/// - `accent` = ส้ม FixGo ใช้กับปุ่ม action และสิ่งที่ผู้ใช้ต้องกดต่อเท่านั้น
abstract final class FixGoColors {
  static const navy = Color(0xFF1D2330);
  static const accent = Color(0xFFF26B1D);
  static const accentActive = Color(0xFFD9560A);

  /// พื้นส้มอ่อน ใช้กับ badge/chip/พื้นหลังไอคอน
  static const accentSoft = Color(0xFFFFF1E7);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF5F6F8);
  static const textPrimary = Color(0xFF1D2330);
  static const textSecondary = Color(0xFF6B7280);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFDC2626);
  static const hairline = Color(0xFFE8EAEE);
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

abstract final class FixGoRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

/// เงานุ่มของการ์ด ใช้แทน elevation ของ Material ที่ดูแข็งเกินไป
const fixGoCardShadow = [
  BoxShadow(
    color: Color(0x0F1D2330),
    blurRadius: 16,
    offset: Offset(0, 4),
  ),
];

ThemeData buildFixGoTheme() {
  const colorScheme = ColorScheme.light(
    primary: FixGoColors.accent,
    onPrimary: Colors.white,
    secondary: FixGoColors.navy,
    onSecondary: Colors.white,
    surface: FixGoColors.background,
    onSurface: FixGoColors.textPrimary,
    error: FixGoColors.error,
    onError: Colors.white,
  );

  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: FixGoColors.surface,
    fontFamily: fixGoFontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: FixGoColors.surface,
      foregroundColor: FixGoColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: fixGoFontFamily,
        color: FixGoColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: FixGoColors.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.lg)),
        side: BorderSide(color: FixGoColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.lg)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: FixGoColors.hairline,
      space: 1,
      thickness: 1,
    ),
    // ปุ่ม action ใช้สีส้มอย่างเดียวทั้งแอป ผู้ใช้จะไม่สับสนว่าต้องกดอะไรต่อ
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: FixGoColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE3E5E9),
        disabledForegroundColor: FixGoColors.textSecondary,
        minimumSize: const Size.fromHeight(56),
        elevation: 0,
        textStyle: const TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: buttonShape,
        textStyle: const TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FixGoColors.accent,
        textStyle: const TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: FixGoColors.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: FixGoColors.accentSoft,
      elevation: 0,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? FixGoColors.accent
              : FixGoColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: fixGoFontFamily,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? FixGoColors.accent
              : FixGoColors.textSecondary,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FixGoColors.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: FixGoColors.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.lg)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: FixGoColors.navy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : FixGoColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? FixGoColors.success
            : FixGoColors.hairline,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: FixGoColors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
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
