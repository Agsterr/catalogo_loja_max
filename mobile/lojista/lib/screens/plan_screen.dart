import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';

/// Mensalidade da loja: situação (teste grátis, paga, vencida, oculta), quanto custa e como pagar. O app do cliente é grátis.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  StorePlan? _plan;
  PaymentInstructions? _pay;
  Object? _error;
  bool _busy = false;

  ApiClient get _api => AppScope.of(context).session.api;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_plan == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final j = await _api.get('/api/store/plan') as Map<String, dynamic>;
      if (mounted) setState(() => _plan = StorePlan.fromJson(j));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _checkout() async {
    setState(() => _busy = true);
    try {
      final j = await _api.post('/api/store/plan/checkout') as Map<String, dynamic>;
      if (mounted) setState(() => _pay = PaymentInstructions.fromJson(j));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Plano e mensalidade')),
      body: p == null
          ? (_error != null ? ErrorRetry(message: 'Não foi possível carregar.', onRetry: () { setState(() => _error = null); _load(); }) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  color: p.visible ? scheme.primaryContainer : scheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(switch (p.state) {
                        'TRIAL' => 'Teste grátis',
                        'ACTIVE' => 'Plano ativo',
                        'GRACE' => 'Mensalidade vencida',
                        _ => 'Loja oculta para os clientes',
                      }, style: t.titleLarge),
                      const SizedBox(height: 6),
                      Text(switch (p.state) {
                        'TRIAL' || 'ACTIVE' => 'Vale até ${date(p.accessUntil)} (${p.daysLeft <= 0 ? 'vence hoje' : p.daysLeft == 1 ? 'falta 1 dia' : 'faltam ${p.daysLeft} dias'}).',
                        'GRACE' => 'Venceu em ${date(p.accessUntil)}. A loja ainda aparece por alguns dias; renove para não sumir.',
                        _ => 'A mensalidade venceu em ${date(p.accessUntil)}. Seus clientes não veem a loja até você renovar. Seus pedidos e produtos estão guardados.',
                      }, style: t.bodyMedium),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Text('${money(p.price)} por mês', style: t.headlineSmall),
                const SizedBox(height: 4),
                Text('O app do cliente é grátis: quem paga é só a loja. Sem comissão sobre as suas vendas, sem limite de pedidos.',
                    style: t.bodyMedium),
                const SizedBox(height: 16),
                if (_pay == null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _checkout,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.pix_rounded),
                    label: Text(p.state == 'TRIAL' ? 'Assinar agora' : 'Renovar mensalidade'),
                  )
                else ...[
                  PixInstructionsCard(instructions: _pay!),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Já paguei, atualizar')),
                ],
                const SizedBox(height: 16),
                Text('Cada pagamento libera 30 dias a partir da confirmação (ou do vencimento, se ainda não venceu). A confirmação '
                    'é feita pela plataforma depois de receber o Pix.', style: t.bodySmall),
              ]),
            ),
    );
  }
}
