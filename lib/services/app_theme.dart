import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors (Sharepool-inspired, but Purple instead of Orange)
  static const Color primary = Color(0xFF7E57C2); // Vibrant Purple
  static const Color primaryDark = Color(0xFF5E35B1); // Deep Purple
  static const Color accent = Color(0xFFB39DDB);  // Light Purple accent
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF1C1C1E);
  static const Color body = Color(0xFF636366);
  static const Color mute = Color(0xFFAEAEB2);
  
  // Light Mode Colors
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color canvasSoft = Color(0xFFF2F2F7);
  static const Color canvasSofter = Color(0xFFF9F9F9);
  
  // Dark Mode Colors
  static const Color darkCanvas = Color(0xFF121212); // Deep Black background
  static const Color darkSurface = Color(0xFF1E1E1E); // Elevated dark cards
  static const Color darkSurfaceHighest = Color(0xFF2C2C2E); // Inputs, active states

  // Premium Gradient for CTAs
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryDark, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Border Radii
  static const double radiusNone = 0.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusPill = 999.0;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        onPrimary: onPrimary,
        surface: canvas,
        onSurface: ink,
        surfaceContainerHighest: canvasSoft,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Inter', fontSize: 52, fontWeight: FontWeight.bold, height: 1.23, color: ink),
        displayMedium: TextStyle(fontFamily: 'Inter', fontSize: 36, fontWeight: FontWeight.bold, height: 1.22, color: ink),
        displaySmall: TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.bold, height: 1.25, color: ink),
        bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500, color: ink),
        bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w400, color: body),
        labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: ink),
        labelSmall: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: mute),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvasSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide(color: Colors.transparent, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        labelStyle: const TextStyle(color: body),
        hintStyle: const TextStyle(color: mute),
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
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: canvas,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(color: canvasSoft, width: 1),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: darkCanvas,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        onPrimary: onPrimary,
        surface: darkSurface,
        onSurface: Colors.white,
        surfaceContainerHighest: darkSurfaceHighest,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Inter', fontSize: 52, fontWeight: FontWeight.bold, height: 1.23, color: Colors.white),
        displayMedium: TextStyle(fontFamily: 'Inter', fontSize: 36, fontWeight: FontWeight.bold, height: 1.22, color: Colors.white),
        displaySmall: TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.bold, height: 1.25, color: Colors.white),
        bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
        bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w400, color: Color(0xFFD1D1D6)),
        labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        labelSmall: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xFF8E8E93)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide(color: Colors.transparent, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        labelStyle: const TextStyle(color: Color(0xFFD1D1D6)),
        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
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
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),
    );
  }

  // Common UI containers dynamically adapting to Theme
  static BoxDecoration cardDecoration(BuildContext context, {double radius = radiusXl, bool hasShadow = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).colorScheme.surface;
    final borderColor = isDark ? Colors.transparent : Theme.of(context).colorScheme.surfaceContainerHighest;
    
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1.0),
      boxShadow: hasShadow
          ? [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.5) : primary.withOpacity(0.08),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 10),
              )
            ]
          : null,
    );
  }
}

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
