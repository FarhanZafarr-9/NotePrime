import 'package:flutter/material.dart';

class AppThemes {
  static ThemeData getTheme(Brightness brightness, ColorScheme? dynamicColorScheme) {
    final colorScheme = dynamicColorScheme ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
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
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 3,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.75,
          ),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        modalBackgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 4,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        dragHandleSize: const Size(36, 4),
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
