import 'package:flutter/material.dart';

/// Automotive Cockpit Dark Mode Palette (Matches Figma Design 1:1)
class CockpitColors {
  static const Color bg = Color(0xFF0D1117);
  static const Color card = Color(0xFF161B22);
  static const Color cardBorder = Color(0xFF262C36);
  static const Color safeGreen = Color(0xFF00E676);
  static const Color dangerRed = Color(0xFFFF1744);
  static const Color warningAmber = Color(0xFFFFB300);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF8B949E);
  static const Color textPrimary = textWhite;
  static const Color background = bg;

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: safeGreen,
      colorScheme: const ColorScheme.dark(
        primary: safeGreen,
        secondary: safeGreen,
        surface: card,
        error: dangerRed,
      ),
      fontFamily: 'Roboto',
      useMaterial3: true,
    );
  }
}

