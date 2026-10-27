import 'package:flutter/material.dart';

/// Identidade da Loja Max: rosé + grafite, cantos arredondados.
class AppTheme {
  AppTheme._();

  static const brand = Color(0xFFB0306A);
  static const sale = Color(0xFFD7263D);

  // "fidelity": mantém o rosé da marca vivo nos botões (o padrão do Material 3 deixa a cor apagada)
  static ThemeData light() =>
      _base(ColorScheme.fromSeed(seedColor: brand, dynamicSchemeVariant: DynamicSchemeVariant.fidelity));

  static ThemeData dark() => _base(ColorScheme.fromSeed(
      seedColor: brand, brightness: Brightness.dark, dynamicSchemeVariant: DynamicSchemeVariant.fidelity));

  static ThemeData _base(ColorScheme scheme) {
    final base = _theme(scheme);
    // texto das etiquetas com a fonte e a cor do tema (sem isso some ou troca de fonte em alguns celulares)
    return base.copyWith(
      chipTheme: base.chipTheme.copyWith(labelStyle: base.textTheme.labelLarge?.copyWith(color: scheme.onSurface)),
    );
  }

  static ThemeData _theme(ColorScheme scheme) => ThemeData(
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
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: scheme.primaryContainer,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
        ),
      );
}
