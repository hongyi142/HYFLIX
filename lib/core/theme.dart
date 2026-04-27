import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color background = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF121821);
  static const Color cardLight = Color(0xFF232A36);
  static const Color cardDark = Color(0xFF1A1F2B);
  static const Color textPrimary = Color(0xFFE5E7EB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color accent = Color(0xFFFF3B40);

  // Spacing
  static const double spacing8 = 8.0;
  static const double spacing16 = 16.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;

  // Border Radius
  static const BorderRadius radius16 = BorderRadius.all(Radius.circular(16.0));
  static const BorderRadius radiusButton = BorderRadius.all(Radius.circular(14.0));
  static const BorderRadius radiusPill = BorderRadius.all(Radius.circular(24.0));

  // Shadows
  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 25.0,
      offset: const Offset(0, 10),
    ),
  ];

  static ThemeData get darkTheme {
    // Uses SF Pro Display when the font asset is loaded.
    // Falls back to system default (San Francisco on Apple, Roboto elsewhere).
    const sfPro = 'SFPro';
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      fontFamily: sfPro,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: sfPro,
          color: textPrimary,
          fontSize: 40,
          fontWeight: FontWeight.w700,
        ),
        displayMedium: TextStyle(
          fontFamily: sfPro,
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          fontFamily: sfPro,
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          fontFamily: sfPro,
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
        bodySmall: TextStyle(
          fontFamily: sfPro,
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
      ),
      useMaterial3: true,
    );
  }
}
