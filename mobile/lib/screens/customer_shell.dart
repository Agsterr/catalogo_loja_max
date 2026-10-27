import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../background.dart';
import '../notifications.dart';
import '../push.dart';
import 'account_screen.dart';
import 'cart_screen.dart';
import 'catalog_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'order_screen.dart';
import 'orders_screen.dart';
import 'product_screen.dart';
import 'store_picker_screen.dart';

/// App do cliente: escolhe a loja e vê a vitrine dela (aberta a todos); pedidos e avisos pedem login.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _unread = 0;
  final _inbox = GlobalKey<NotificationsScreenState>();

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
    if (state == AppLifecycleState.resumed) _checkAlerts();
  }

  /// App aberto: confere o sino (e mostra aviso local do que for novo, quando não há push).
  Future<void> _checkAlerts() async {
    final session = AppScope.of(context).session;
    if (!session.signedIn) return;
    try {
      await notifyNewAlerts(session.api);
      _inbox.currentState?.refresh();
    } catch (_) {}
  }

  void _onTapped() {
    final payload = LocalNotifications.instance.tapped.value;
    if (payload == null || payload.isEmpty || !mounted) return;
    LocalNotifications.instance.tapped.value = null;
    open(payload);
  }

  /// Abre o pedido/produto do aviso, na loja dele (o cliente recebe avisos de todas em que comprou).
  void open(String payload) {
    final scope = AppScope.of(context);
    final target = parsePayload(payload);
    final slug = target?.slug ?? scope.store.slug;
    if (target == null || slug == null) return;
    if (target.kind == 'order' && scope.session.signedIn) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => OrderScreen(api: scope.session.api, orderId: target.id, slug: slug)));
    } else if (target.kind == 'product') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProductScreen(api: scope.session.api, slug: slug, productId: target.id)));
    }
  }

  String? _followed;

  /// Loja aberta: o celular passa a receber as promoções dela; app de loja fixa busca o nome.
  void _storeOpened(String slug) {
    if (_followed == slug) return;
    _followed = slug;
    Push.follow(slug);
    final store = AppScope.of(context).store;
    if (store.store?.name.isEmpty ?? false) {
      AppScope.of(context).session.api.get('/api/public/stores/$slug').then((j) {
        store.rename((j as Map<String, dynamic>)['name'] as String);
      }).catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(listenable: scope.store, builder: (context, _) => _build(context, scope));
  }

  Widget _build(BuildContext context, AppScope scope) {
    final session = scope.session;
    final store = scope.store.store;
    if (store == null) return StorePickerScreen(api: session.api);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _storeOpened(store.slug);
    });
    Widget needsLogin(String text) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(text, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Entrar ou criar conta'),
                ),
              ]),
            ),
          ),
        );
    final pages = [
      CatalogScreen(
        key: ValueKey('vitrine-${store.slug}'),
        api: session.api,
        slug: store.slug,
        storeName: store.name,
        onSwitchStore: scope.store.fixed ? null : scope.store.leave,
      ),
      const CartScreen(),
      session.signedIn
          ? OrdersScreen(key: ValueKey('pedidos-${store.slug}'), api: session.api, slug: store.slug)
          : needsLogin('Entre para ver seus pedidos.'),
      session.signedIn
          ? NotificationsScreen(key: _inbox, session: session, onOpen: open, onUnread: (n) => setState(() => _unread = n))
          : needsLogin('Entre para receber os avisos dos seus pedidos.'),
      const AccountScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: ListenableBuilder(
        listenable: scope.cart,
        builder: (context, _) => NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            if (i == 3) _inbox.currentState?.refresh();
          },
          destinations: [
            const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Vitrine'),
            NavigationDestination(
              icon: Badge(isLabelVisible: scope.cart.count > 0, label: Text('${scope.cart.count}'), child: const Icon(Icons.shopping_bag_outlined)),
              selectedIcon: const Icon(Icons.shopping_bag),
              label: 'Carrinho',
            ),
            const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pedidos'),
            NavigationDestination(
              icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.notifications_outlined)),
              selectedIcon: const Icon(Icons.notifications),
              label: 'Avisos',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Conta'),
          ],
        ),
      ),
    );
  }
}
