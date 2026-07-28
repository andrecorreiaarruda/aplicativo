import 'package:flutter/material.dart';

abstract final class OrionColors {
  static const navy = Color(0xFF071A4B);
  static const deepNavy = Color(0xFF041132);
  static const blue = Color(0xFF087AA6);
  static const cyan = Color(0xFF18A9C4);
  static const paleCyan = Color(0xFFE8F7FA);
  static const canvas = Color(0xFFF4F7FB);
  static const ink = Color(0xFF14213D);
  static const muted = Color(0xFF61708C);
  static const border = Color(0xFFD9E2EF);
  static const success = Color(0xFF18794E);
  static const warning = Color(0xFFA45B00);
  static const danger = Color(0xFFB42318);
}

abstract final class OrionTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: OrionColors.blue,
      brightness: Brightness.light,
    ).copyWith(
      primary: OrionColors.navy,
      secondary: OrionColors.cyan,
      surface: Colors.white,
      error: OrionColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: OrionColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: OrionColors.navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: OrionColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: OrionColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: OrionColors.blue, width: 1.6),
        ),
        alignLabelWithHint: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: OrionColors.border),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: OrionColors.deepNavy,
        indicatorColor: OrionColors.cyan,
        selectedIconTheme: IconThemeData(color: OrionColors.deepNavy),
        unselectedIconTheme: IconThemeData(color: Color(0xFFB9C8E8)),
        selectedLabelTextStyle:
            TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: Color(0xFFB9C8E8)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: OrionColors.paleCyan,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: OrionColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: OrionColors.navy,
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: OrionColors.border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: OrionColors.navy,
        foregroundColor: Colors.white,
      ),
      dividerTheme: const DividerThemeData(color: OrionColors.border),
    );
  }

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: OrionColors.cyan,
          brightness: Brightness.dark,
        ),
      );
}
