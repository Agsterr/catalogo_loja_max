import 'package:flutter/widgets.dart';

import 'cart.dart';
import 'session.dart';

/// Sessão e carrinho disponíveis para todas as telas (sem framework de estado: só ChangeNotifier).
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.session, required this.cart, required super.child});

  final Session session;
  final Cart cart;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => session != oldWidget.session || cart != oldWidget.cart;
}
