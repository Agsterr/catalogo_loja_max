import 'package:flutter/widgets.dart';
import 'package:loja_core/loja_core.dart';

/// Sessão disponível para todas as telas do app do entregador.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.session, required super.child});

  final Session session;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => session != oldWidget.session;
}
