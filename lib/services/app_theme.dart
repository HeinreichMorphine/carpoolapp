import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors
  static const Color primary = Color(0xFF000000);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF000000);
  static const Color body = Color(0xFF5E5E5E);
  static const Color mute = Color(0xFFAFAFAF);
  static const Color hairlineMid = Color(0xFF4B4B4B);
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color canvasSoft = Color(0xFFEFEFEF);
  static const Color canvasSofter = Color(0xFFF3F3F3);
  static const Color surfacePressed = Color(0xFFE2E2E2);
  static const Color link = Color(0xFF0000EE);

  // Border Radii
  static const double radiusNone = 0.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusPill = 999.0;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        surface: canvas,
        onSurface: ink,
        surfaceContainerHighest: canvasSoft,
      ),
      textTheme: const TextTheme(
        // Display - UberMove equivalent
        displayLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 52,
          fontWeight: FontWeight.bold,
          height: 1.23,
          color: ink,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 36,
          fontWeight: FontWeight.bold,
          height: 1.22,
          color: ink,
        ),
        displaySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.bold,
          height: 1.25,
          color: ink,
        ),
        // Body - UberMoveText equivalent
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: body,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: mute,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvasSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: body),
        floatingLabelStyle: const TextStyle(color: primary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Common UI containers
  static BoxDecoration cardDecoration({Color color = canvas, double radius = radiusXl, bool hasShadow = false}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: color == canvas ? Border.all(color: canvasSoft, width: 1) : null,
      boxShadow: hasShadow
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              )
            ]
          : null,
    );
  }
}
