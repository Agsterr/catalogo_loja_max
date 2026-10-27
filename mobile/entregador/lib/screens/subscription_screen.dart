import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loja_core/loja_core.dart';

import '../courier_api.dart';

/// Entregas grátis e assinatura (R$ 24,99/mês): situação, "Assinar" e as instruções de Pix.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.api, this.message});

  final CourierApi api;

  /// Aviso de quem mandou para cá (ex.: acabaram as entregas grátis).
  final String? message;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  CourierSubscription? _sub;
  PaymentInstructions? _pay;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.subscription();
      if (mounted) {
        setState(() {
          _sub = s;
          _error = null;
          if (s.subscribed) _pay = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    try {
      final p = await widget.api.checkout();
      if (mounted) setState(() => _pay = p);
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
    final s = _sub;
    return Scaffold(
      appBar: AppBar(title: const Text('Assinatura')),
      body: s == null
          ? (_error != null
              ? ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (widget.message != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)),
                    child: Text(widget.message!, style: t.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
                  ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
                  child: Column(children: [
                    Icon(s.subscribed ? Icons.verified_rounded : Icons.card_giftcard_rounded, size: 44, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text(
                        s.subscribed
                            ? 'Assinatura ativa${s.paidUntil == null ? '' : ' até ${date(s.paidUntil!)}'}'
                            : '${s.freeLeft} de ${s.freeLimit} entregas grátis restantes',
                        textAlign: TextAlign.center,
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        s.subscribed
                            ? 'Corridas sem limite enquanto a assinatura estiver ativa.'
                            : 'Depois das entregas grátis, a assinatura é de ${money(s.price)} por mês.',
                        textAlign: TextAlign.center,
                        style: t.bodyMedium),
                  ]),
                ),
                const SizedBox(height: 12),
                Text('O frete é pago direto a você pelo cliente ou pela loja. A plataforma não fica com nada das entregas: '
                    'a assinatura é o único valor cobrado.', style: t.bodySmall),
                const SizedBox(height: 16),
                if (_pay == null) ...[
                  FilledButton(
                    onPressed: _busy ? null : _subscribe,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(s.subscribed ? 'Renovar · ${money(s.price)}' : 'Assinar · ${money(s.price)}/mês'),
                  ),
                ] else
                  _PaymentCard(pay: _pay!, onRefresh: _load),
              ]),
            ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.pay, required this.onRefresh});

  final PaymentInstructions pay;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!pay.configured)
            Text(pay.message, style: t.bodyLarge)
          else ...[
            Text('Pague por Pix', style: t.titleMedium),
            const SizedBox(height: 8),
            Text('Valor', style: t.bodySmall),
            Text(money(pay.amount), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
            const SizedBox(height: 8),
            Text('Chave Pix', style: t.bodySmall),
            Row(children: [
              Expanded(child: SelectableText(pay.pixKey!, style: t.titleMedium)),
              IconButton.filledTonal(
                tooltip: 'Copiar chave',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: pay.pixKey!));
                  if (context.mounted) showInfo(context, 'Chave Pix copiada.');
                },
              ),
            ]),
            if (pay.holder != null) ...[
              const SizedBox(height: 4),
              Text('Titular', style: t.bodySmall),
              Text(pay.holder!, style: t.bodyLarge),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text('Código de referência', style: t.bodySmall),
                SelectableText(pay.reference, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 3)),
              ]),
            ),
            const SizedBox(height: 8),
            Text(pay.message, style: t.bodyMedium),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Já paguei, atualizar')),
        ]),
      ),
    );
  }
}
