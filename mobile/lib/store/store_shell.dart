import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../background.dart';
import '../notifications.dart';
import '../screens/notifications_screen.dart';
import '../screens/order_screen.dart';
import 'more_screen.dart';
import 'product_form_screen.dart';
import 'store_orders_screen.dart';
import 'store_products_screen.dart';

/// Gestão da loja (dono e funcionários): pedidos, produtos/estoque, avisos e mais.
class StoreShell extends StatefulWidget {
  const StoreShell({super.key});

  @override
  State<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends State<StoreShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _unread = 0;
  final _inbox = GlobalKey<NotificationsScreenState>();
  final _orders = GlobalKey<StoreOrdersScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalNotifications.instance.tapped.addListener(_onTapped);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTapped());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalNotifications.instance.tapped.removeListener(_onTapped);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      await notifyNewAlerts(AppScope.of(context).session.api);
    } catch (_) {}
    _inbox.currentState?.refresh();
    _orders.currentState?.refresh();
  }

  void _onTapped() {
    final payload = LocalNotifications.instance.tapped.value;
    if (payload == null || payload.isEmpty || !mounted) return;
    LocalNotifications.instance.tapped.value = null;
    _open(payload);
  }

  void _open(String payload) {
    final api = AppScope.of(context).session.api;
    final id = int.tryParse(payload.split(':').last);
    if (id == null) return;
    if (payload.startsWith('order:')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(api: api, orderId: id, team: true)))
          .then((_) => _orders.currentState?.refresh());
    } else if (payload.startsWith('product:')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(api: api, productId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        StoreOrdersScreen(key: _orders, api: session.api),
        StoreProductsScreen(api: session.api),
        NotificationsScreen(key: _inbox, session: session, onOpen: _open, onUnread: (n) => setState(() => _unread = n)),
        const MoreScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 2) _inbox.currentState?.refresh();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pedidos'),
          const NavigationDestination(icon: Icon(Icons.checkroom_outlined), selectedIcon: Icon(Icons.checkroom), label: 'Produtos'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.notifications_outlined)),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Avisos',
          ),
          const NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'Mais'),
        ],
      ),
    );
  }
}
