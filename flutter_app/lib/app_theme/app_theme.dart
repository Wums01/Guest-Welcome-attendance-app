import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ── Core palette (Stitch design system) ─────────────────────────────────────
  static const Color primary    = Color(0xFF0F49BD); // blue-700
  static const Color primaryBg  = Color(0xFFEFF6FF); // blue-50
  static const Color surface    = Colors.white;
  static const Color background = Color(0xFFF6F6F8); // Stitch background
  static const Color slate200   = Color(0xFFE2E8F0); // card borders
  static const Color slate500   = Color(0xFF64748B); // secondary text

  // ── Status colours ───────────────────────────────────────────────────────────
  static const Color success    = Color(0xFF22C55E); // green-500  (present)
  static const Color successBg  = Color(0xFFDCFCE7); // green-100
  static const Color error      = Color(0xFFEF4444); // red-500    (absent)
  static const Color errorBg    = Color(0xFFFEE2E2); // red-100
  static const Color amber      = Color(0xFFF59E0B); // amber-500  (excused / anniversaries)
  static const Color amberBg    = Color(0xFFFEF3C7); // amber-100

  // ── Team badge colours ───────────────────────────────────────────────────────
  static const Color teamABg      = Color(0xFFEFF6FF);
  static const Color teamAText    = Color(0xFF0F49BD);
  static const Color teamBBg      = Color(0xFFF0FDF4);
  static const Color teamBText    = Color(0xFF16A34A);
  static const Color teamCBg      = Color(0xFFFAF5FF);
  static const Color teamCText    = Color(0xFF7C3AED);
  static const Color teamNoneBg   = Color(0xFFF1F5F9);
  static const Color teamNoneText = Color(0xFF64748B);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      textTheme: GoogleFonts.poppinsTextTheme(),

      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: slate200),
        ),
        color: surface,
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          elevation: 0,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: slate200),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: slate500, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: background,
        selectedColor: primary,
        disabledColor: background,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        side: const BorderSide(color: slate200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}
