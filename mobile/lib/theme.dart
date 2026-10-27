import 'package:flutter/material.dart';

/// Identidade da Loja Max: rosé + grafite, cantos arredondados.
class AppTheme {
  AppTheme._();

  static const brand = Color(0xFFB0306A);
  static const sale = Color(0xFFD7263D);

  static ThemeData light() => _base(ColorScheme.fromSeed(seedColor: brand));

  static ThemeData dark() => _base(ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark));

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: scheme.surface, scrolledUnderElevation: 1),
        cardTheme: CardThemeData(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        // texto das etiquetas com cor explícita (em alguns celulares sumia no tema padrão)
        chipTheme: ChipThemeData(labelStyle: TextStyle(color: scheme.onSurface)),
      );
}
