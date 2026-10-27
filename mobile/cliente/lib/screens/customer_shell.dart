import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';
import 'cart_screen.dart';
import 'catalog_screen.dart';
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
  final _cartScreen = GlobalKey<CartScreenState>();
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalNotifications.instance.tapped.addListener(_onTapped);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTapped());
    _listenLinks();
  }

  /// Link de produto compartilhado (`lojamax://loja/SLUG/produto/ID`): abre a loja e a peça.
  Future<void> _listenLinks() async {
    try {
      final links = AppLinks();
      final first = await links.getInitialLink();
      if (first != null) _openLink(first);
      _links = links.uriLinkStream.listen(_openLink);
    } catch (_) {
      // plataforma sem suporte a links (testes): o app funciona normal
    }
  }

  void _openLink(Uri uri) {
    final seg = uri.pathSegments;
    if (uri.scheme != 'lojamax' || seg.length < 3 || seg[1] != 'produto') return;
    final slug = seg[0];
    final id = int.tryParse(seg[2]);
    if (id == null || !RegExp(r'^[a-z0-9-]{3,60}$').hasMatch(slug) || !mounted) return;
    final scope = AppScope.of(context);
    if (scope.store.slug != slug && !scope.store.fixed) scope.store.open(StoreCard(slug: slug, name: ''));
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProductScreen(api: scope.session.api, slug: slug, productId: id)));
  }

  @override
  void dispose() {
    _links?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    LocalNotifications.instance.tapped.removeListener(_onTapped);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // quem deixa o app em segundo plano por dias não é deslogado: o token é renovado ao voltar
      AppScope.of(context).session.refreshIfDue();
      _checkAlerts();
    }
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
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(session: AppScope.of(context).session))),
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
      CartScreen(key: _cartScreen),
      session.signedIn
          ? OrdersScreen(key: ValueKey('pedidos-${store.slug}'), api: session.api, slug: store.slug)
          : needsLogin('Entre para ver seus pedidos.'),
      session.signedIn
          ? NotificationsScreen(key: _inbox, session: session, onOpen: open, onUnread: (n) => setState(() => _unread = n))
          : needsLogin('Entre para receber os avisos dos seus pedidos.'),
      AccountScreen(
        key: ValueKey('conta-${store.slug}'),
        session: session,
        loadStore: () async => StoreInfo.fromJson(await session.api.get('/api/public/stores/${store.slug}') as Map<String, dynamic>),
        onSignIn: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(session: session))),
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: ListenableBuilder(
        listenable: scope.cart,
        builder: (context, _) => NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            setState(() => _tab = i);
            if (i == 1) _cartScreen.currentState?.refresh();
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
