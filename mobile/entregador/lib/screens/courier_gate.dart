import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';
import '../courier_api.dart';
import 'courier_shell.dart';

/// Escolhe a tela pelo status do cadastro: em análise, bloqueado ou liberado (as abas).
class CourierGate extends StatefulWidget {
  const CourierGate({super.key, this.api});

  /// Para testes; no app vem da sessão.
  final CourierApi? api;

  @override
  State<CourierGate> createState() => _CourierGateState();
}

class _CourierGateState extends State<CourierGate> with WidgetsBindingObserver {
  CourierProfile? _profile;
  Object? _error;
  bool _loading = true;

  CourierApi get _api => widget.api ?? CourierApi(AppScope.of(context).session.api);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !(_profile?.approved ?? false)) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _api.me();
      if (mounted) {
        setState(() {
          _profile = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (p == null) {
      return Scaffold(
        body: _error != null
            ? ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: _load)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (p.approved) {
      return CourierShell(profile: p, api: widget.api, onProfile: (np) => setState(() => _profile = np));
    }
    final session = AppScope.of(context).session;
    final blocked = p.status == 'BLOCKED';
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 60),
            Icon(blocked ? Icons.block_rounded : Icons.hourglass_top_rounded, size: 72,
                color: blocked ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(blocked ? 'Cadastro bloqueado' : 'Cadastro em análise',
                textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                blocked
                    ? (p.statusReason ?? 'Fale com o suporte da plataforma.')
                    : 'Recebemos seu cadastro, ${p.name.split(' ').first}. Assim que a plataforma aprovar, você será avisado e '
                        'poderá ligar o app para receber corridas.',
                textAlign: TextAlign.center, style: t.bodyLarge),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Atualizar'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: session.logout, child: const Text('Sair')),
          ]),
        ),
      ),
    );
  }
}
