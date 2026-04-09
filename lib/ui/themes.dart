import 'package:flutter/material.dart';

class AppThemes {
  static ThemeData getTheme(Brightness brightness, ColorScheme? dynamicColorScheme) {
    final colorScheme = dynamicColorScheme ?? ColorScheme.fromSeed(
      seedColor: Colors.white,
      brightness: brightness,
    );

    return ThemeData(
      fontFamily: 'Inter',
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 40),
        ),
      ),
    );
  }

  static final lightTheme = getTheme(Brightness.light, null);
  static final darkTheme = getTheme(Brightness.dark, null);
}
