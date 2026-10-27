import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:loja_core/loja_core.dart';

import 'app_scope.dart';
import 'device_id.dart';
import 'screens/courier_gate.dart';
import 'screens/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await LocalNotifications.instance.init();
  final session = Session();
  // todas as chamadas levam o ID do aparelho (5 entregas grátis por aparelho e CPF)
  session.api.defaultHeaders['X-Device-Id'] = await deviceId();
  await session.restore();
  runApp(EntregadorApp(session: session));
  Push.askPermissionOnce();
  Push.start(session);
  scheduleBackgroundChecks();
}

/// Loja Max Entregador: cadastro, mural de corridas da região, entrega com códigos e ganhos.
class EntregadorApp extends StatefulWidget {
  const EntregadorApp({super.key, required this.session});

  final Session session;

  @override
  State<EntregadorApp> createState() => _EntregadorAppState();
}

class _EntregadorAppState extends State<EntregadorApp> {
  final _navigator = GlobalKey<NavigatorState>();

  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.addListener(_backToRoot);
  }

  @override
  void dispose() {
    session.removeListener(_backToRoot);
    super.dispose();
  }

  /// Saída, bloqueio ou troca de conta com telas abertas: volta para a raiz.
  void _backToRoot() {
    if (session.state != SessionState.restoring && session.state != SessionState.signedIn) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: session,
      child: MaterialApp(
        title: 'Loja Max Entregador',
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
            SessionState.offline => Scaffold(body: ErrorRetry(message: 'Sem conexão.', onRetry: session.restore)),
            SessionState.blocked => BlockedScreen(
                reason: session.blockedReason ?? AccountBlockedException.defaultReason,
                onSignOut: session.signOut,
              ),
            SessionState.signedOut => WelcomeScreen(session: session),
            _ when session.user?.isCourier ?? false => CourierGate(key: ValueKey(session.user!.id)),
            _ => WrongAppScreen(
                message: 'Esta conta não é de entregador. Para comprar, use o app Loja Max; para vender, o Loja Max Lojista. '
                    'Para entregar, saia e toque em "Quero ser entregador".',
                onSignOut: session.logout,
              ),
          },
        ),
      ),
    );
  }
}
