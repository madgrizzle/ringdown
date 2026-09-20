import 'package:flutter/material.dart';

class RingdownColors {
  static const seed = Color(0xFFE53935);
  static const activeUnacked = Color(0xFFE53935);
  static const activeAcked = Color(0xFFFB8C00);
  static const cleared = Color(0xFF66BB6A);
  static const unackedAmber = Color(0xFFFFC107);
  static const darkBg = Color(0xFF0E0E0E);
  static const darkSurface = Color(0xFF161616);
  static const darkCard = Color(0xFF1C1C1C);
}

ThemeData ringdownTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: RingdownColors.seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: isDark ? RingdownColors.darkBg : scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: isDark ? RingdownColors.darkSurface : scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: isDark ? RingdownColors.darkCard : scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    ),
  );
}
