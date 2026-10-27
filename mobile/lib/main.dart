import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api_client.dart';
import 'app_scope.dart';
import 'background.dart';
import 'cart.dart';
import 'notifications.dart';
import 'push.dart';
import 'session.dart';
import 'screens/blocked_screen.dart';
import 'screens/customer_shell.dart';
import 'store/store_shell.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await LocalNotifications.instance.init();
  final session = Session();
  final cart = Cart();
  await cart.load();
  await session.restore();
  runApp(LojaApp(session: session, cart: cart));
  Push.askPermissionOnce();
  Push.start(session);
  scheduleBackgroundChecks();
}

class LojaApp extends StatefulWidget {
  const LojaApp({super.key, required this.session, required this.cart});

  final Session session;
  final Cart cart;

  @override
  State<LojaApp> createState() => _LojaAppState();
}

class _LojaAppState extends State<LojaApp> {
  final _navigator = GlobalKey<NavigatorState>();

  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    _lastState = session.state;
    _lastUser = session.user?.id;
    session.addListener(_backToRoot);
  }

  @override
  void dispose() {
    session.removeListener(_backToRoot);
    super.dispose();
  }

  SessionState? _lastState;
  int? _lastUser;

  /// Bloqueio, saída ou troca de conta com telas abertas: volta para a raiz (vitrine, gestão ou bloqueio).
  /// Login feito por cima da vitrine não conta: a própria tela de login volta para onde estava.
  void _backToRoot() {
    final state = session.state;
    final user = session.user?.id;
    final changed = state != _lastState || user != _lastUser;
    final wasSignedIn = _lastState == SessionState.signedIn;
    _lastState = state;
    _lastUser = user;
    if (changed && state != SessionState.restoring && (wasSignedIn || state == SessionState.blocked)) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: session,
      cart: widget.cart,
      child: MaterialApp(
        title: 'Loja Max',
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3)),
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) => switch (session.state) {
            SessionState.restoring => const Scaffold(body: Center(child: CircularProgressIndicator())),
            SessionState.offline =>
              Scaffold(body: ErrorRetry(message: 'Sem conexão com a loja.', onRetry: session.restore)),
            SessionState.blocked => BlockedScreen(
                reason: session.blockedReason ?? AccountBlockedException.defaultReason,
                onSignOut: session.signOut,
              ),
            _ when session.user?.isTeam ?? false => StoreShell(key: ValueKey(session.user!.id)),
            _ => const CustomerShell(),
          },
        ),
      ),
    );
  }
}
