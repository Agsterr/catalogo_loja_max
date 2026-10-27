import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';
import '../courier_api.dart';
import 'account_tab.dart';
import 'active_screen.dart';
import 'board_screen.dart';
import 'earnings_screen.dart';

/// Entregador aprovado: Corridas (mural), Em andamento, Ganhos e Conta.
class CourierShell extends StatefulWidget {
  const CourierShell({super.key, required this.profile, required this.onProfile, this.api, this.locate = safeLocate});

  final CourierProfile profile;
  final ValueChanged<CourierProfile> onProfile;

  /// Para testes; no app vem da sessão.
  final CourierApi? api;
  final Future<GeoPoint?> Function() locate;

  @override
  State<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends State<CourierShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _activeCount = 0;
  bool _foreground = true;
  final _board = GlobalKey<BoardScreenState>();
  final _active = GlobalKey<ActiveScreenState>();

  CourierApi get _api => widget.api ?? CourierApi(AppScope.of(context).session.api);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalNotifications.instance.tapped.addListener(_onTapped);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalNotifications.instance.tapped.removeListener(_onTapped);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      AppScope.of(context).session.refreshIfDue();
      _board.currentState?.refresh();
      _active.currentState?.refresh();
    }
  }

  /// Toque num aviso de corrida: abre o mural (e confere as corridas em andamento).
  void _onTapped() {
    if (LocalNotifications.instance.tapped.value == null) return;
    LocalNotifications.instance.tapped.value = null;
    setState(() => _tab = 0);
    _board.currentState?.refresh();
    _active.currentState?.refresh();
  }

  void _accepted() {
    setState(() => _tab = 1);
    _active.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        BoardScreen(
          key: _board,
          api: api,
          profile: widget.profile,
          onProfile: widget.onProfile,
          onAccepted: _accepted,
          locate: widget.locate,
          visible: _tab == 0 && _foreground,
        ),
        ActiveScreen(key: _active, api: api, onCount: (n) => setState(() => _activeCount = n), onChanged: () => _board.currentState?.refresh()),
        EarningsScreen(api: api, visible: _tab == 2),
        AccountTab(api: api, profile: widget.profile, onProfile: widget.onProfile),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _active.currentState?.refresh();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Corridas'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _activeCount > 0, label: Text('$_activeCount'), child: const Icon(Icons.two_wheeler_outlined)),
            selectedIcon: Badge(isLabelVisible: _activeCount > 0, label: Text('$_activeCount'), child: const Icon(Icons.two_wheeler)),
            label: 'Em andamento',
          ),
          const NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Ganhos'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Conta'),
        ],
      ),
    );
  }
}
