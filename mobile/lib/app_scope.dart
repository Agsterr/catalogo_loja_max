import 'package:flutter/widgets.dart';

import 'cart.dart';
import 'current_store.dart';
import 'session.dart';

/// Sessão, loja aberta e carrinho disponíveis para todas as telas (sem framework de estado: só ChangeNotifier).
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.session, required this.cart, required this.store, required super.child});

  final Session session;
  final Cart cart;
  final CurrentStore store;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      session != oldWidget.session || cart != oldWidget.cart || store != oldWidget.store;
}
