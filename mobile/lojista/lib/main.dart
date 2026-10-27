import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:loja_core/loja_core.dart';

import 'app_scope.dart';
import 'platform/platform_shell.dart';
import 'screens/store_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await LocalNotifications.instance.init();
  final session = Session();
  await session.restore();
  runApp(LojistaApp(session: session));
  Push.askPermissionOnce();
  Push.start(session);
  scheduleBackgroundChecks();
}

/// Loja Max Lojista: gestão da loja (dono e funcionários) e painel do administrador da plataforma.
class LojistaApp extends StatefulWidget {
  const LojistaApp({super.key, required this.session});

  final Session session;

  @override
  State<LojistaApp> createState() => _LojistaAppState();
}

class _LojistaAppState extends State<LojistaApp> {
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
        title: 'Loja Max Lojista',
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
            SessionState.offline => Scaffold(body: ErrorRetry(message: 'Sem conexão com a loja.', onRetry: session.restore)),
            SessionState.blocked => BlockedScreen(
                reason: session.blockedReason ?? AccountBlockedException.defaultReason,
                onSignOut: session.signOut,
              ),
            SessionState.signedOut => LoginScreen(session: session, forStore: true, popOnSuccess: false),
            _ when session.user?.isTeam ?? false => StoreShell(key: ValueKey(session.user!.id)),
            _ when session.user?.isPlatformAdmin ?? false => const PlatformShell(),
            _ => WrongAppScreen(
                message: 'Esta é uma conta de cliente. Para comprar, use o app Loja Max. '
                    'Para vender, saia e toque em "Abrir minha loja".',
                onSignOut: session.logout,
              ),
          },
        ),
      ),
    );
  }
}
