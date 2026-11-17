// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:material_ui/material_ui.dart';

/// Playground palette and text styles.
class PlaygroundColors {
  static const background = Color(0xFF050B18);
  static const surface = Color(0xFF0A1428);
  static const card = Color(0xFF09142C);
  static const primary = Color(0xFF3688FF);
  static const primaryDeep = Color(0xFF2060C8);
  static const primarySoft = Color(0xFF9CC4FF);
  static const accent = Color(0xFF8BF9FA);
  static const pass = Color(0xFF34D399);
  static const passSoft = Color(0xFF6EE7B7);
  static const fail = Color(0xFFEF4444);
  static const failSoft = Color(0xFFFCA5A5);
  static const idle = Color(0xFF94A3B8);
  static const warn = Color(0xFFF59E0B);
  static const warnSoft = Color(0xFFFCD34D);

  static Color white(double opacity) => Colors.white.withValues(alpha: opacity);

  static const primaryGradient = LinearGradient(colors: [primary, primaryDeep]);
  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFA09142C), Color(0xFF040A18)],
  );
}

class PlaygroundTheme {
  static const mono = 'monospace';
  static const monoFallback = ['JetBrains Mono', 'Menlo', 'Courier'];

  static TextStyle monoStyle({double size = 12, Color? color, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        color: color ?? PlaygroundColors.white(0.55),
        fontWeight: weight,
        height: 1.4,
      );

  static ThemeData app() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: PlaygroundColors.primary,
      scaffoldBackgroundColor: PlaygroundColors.background,
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: PlaygroundColors.primary,
        surface: PlaygroundColors.background,
      ),
      textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: PlaygroundColors.surface),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Theme used inside the component preview, so stories render in light or dark mode.
  static ThemeData preview({required bool dark}) => ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        colorSchemeSeed: PlaygroundColors.primary,
      );
}
