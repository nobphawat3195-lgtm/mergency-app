import 'package:flutter/material.dart';

/// สีแบรนด์ FixGo — โทนเขียว สื่อความปลอดภัย/พร้อมช่วยเหลือ พื้นมิ้นต์อ่อน + การ์ดขาว
///
/// ชื่อ `navy`/`accent` เก็บไว้ตามเดิมเพื่อไม่ต้องแก้ทุกไฟล์ที่อ้างอิง
/// - `navy`   = สีหมึกเข้ม #122821 ใช้กับหัวข้อ ตัวเลขราคา และการ์ดพื้นเข้ม
/// - `accent` = เขียวเข้ม #0B5F45 ใช้กับปุ่ม action และสิ่งที่ผู้ใช้ต้องกดต่อ
///
/// ค่า contrast (WCAG) ที่ตรวจแล้ว: ขาวบน accent 7.67, ink บน lime 11.79,
/// textSecondary บนมิ้นต์ 6.05, jade บนขาว 3.20 (ใช้กับไอคอน/ตัวใหญ่เท่านั้น)
abstract final class FixGoColors {
  static const navy = Color(0xFF122821);
  static const accent = Color(0xFF0B5F45);
  static const accentActive = Color(0xFF084A36);

  /// พื้นมิ้นต์ ใช้กับ badge/chip/พื้นหลังไอคอน และพื้นหลังหน้าจอ
  static const accentSoft = Color(0xFFECF8F1);

  /// เขียวหยก ใช้กับไอคอน เส้นกราฟ ขอบเน้น ห้ามใช้เป็นสีตัวอักษรขนาดเล็กบนพื้นขาว
  static const jade = Color(0xFF16A37B);

  /// สีเน้นเขียวมะนาว ใช้เป็นพื้นของ badge/ปุ่มรองบนพื้นเขียวเข้ม คู่กับตัวอักษร ink
  static const lime = Color(0xFFC7EE77);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFECF8F1);
  static const textPrimary = Color(0xFF122821);
  static const textSecondary = Color(0xFF4A6259);
  static const success = Color(0xFF0E7A57);
  static const warning = Color(0xFF9A5B00);
  static const error = Color(0xFFC62828);
  static const hairline = Color(0xFFD5E8DE);

  /// ปุ่มที่กดไม่ได้: contrast 3.84 (เกณฑ์ UI component 3:1)
  static const disabledBackground = Color(0xFFE3EBE7);
  static const disabledForeground = Color(0xFF5F7A70);

  /// พื้นการ์ดเข้มฝั่งช่าง/hero
  static const ink = navy;
}

/// gradient ของการ์ด hero/ฉุกเฉิน ขาวบนทั้งสองปลาย contrast >= 7.6
const fixGoBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [FixGoColors.accent, FixGoColors.accentActive],
);

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
    color: Color(0x14122821),
    blurRadius: 16,
    offset: Offset(0, 4),
  ),
];

ThemeData buildFixGoTheme() {
  const colorScheme = ColorScheme.light(
    primary: FixGoColors.accent,
    onPrimary: Colors.white,
    secondary: FixGoColors.jade,
    onSecondary: FixGoColors.navy,
    tertiary: FixGoColors.lime,
    onTertiary: FixGoColors.navy,
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
    // ปุ่ม action ใช้เขียวเข้มอย่างเดียวทั้งแอป ผู้ใช้จะไม่สับสนว่าต้องกดอะไรต่อ
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: FixGoColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: FixGoColors.disabledBackground,
        disabledForegroundColor: FixGoColors.disabledForeground,
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
        foregroundColor: FixGoColors.accent,
        disabledForegroundColor: FixGoColors.disabledForeground,
        side: const BorderSide(color: FixGoColors.accent, width: 1.5),
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
            ? FixGoColors.jade
            : FixGoColors.hairline,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: FixGoColors.background,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
        borderSide: BorderSide(color: FixGoColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
        borderSide: BorderSide(color: FixGoColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
        borderSide: BorderSide(color: FixGoColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(FixGoRadius.md)),
        borderSide: BorderSide(color: FixGoColors.error, width: 1.5),
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
