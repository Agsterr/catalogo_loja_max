import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Pedido com itens, valores e linha do tempo. Com [team] mostra o cliente e as ações da loja
/// (confirmar, pronto/saiu para entrega, entregue, cancelar, pago).
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.api, required this.orderId, this.team = false});

  final ApiClient api;
  final int orderId;
  final bool team;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Order? _order;
  Object? _error;
  bool _busy = false;

  String get _path => widget.team ? '/api/store/orders/${widget.orderId}' : '/api/orders/${widget.orderId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final o = Order.fromJson(await widget.api.get(_path) as Map<String, dynamic>);
      if (mounted) setState(() => _order = o);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<dynamic> Function() call) async {
    setState(() => _busy = true);
    try {
      final o = Order.fromJson(await call() as Map<String, dynamic>);
      if (mounted) setState(() => _order = o);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason(String title) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLength: 300, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancelar pedido')),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _changeStatus(OrderStatus to) async {
    String? note;
    if (to == OrderStatus.canceled) {
      note = await _askReason('Cancelar o pedido?');
      if (note == null) return;
    }
    await _act(() => widget.api.post('/api/store/orders/${widget.orderId}/status', {'status': to.api, 'note': note}));
  }

  Future<void> _cancelMine() async {
    final reason = await _askReason('Cancelar seu pedido?');
    if (reason == null) return;
    await _act(() => widget.api.post('/api/orders/${widget.orderId}/cancel', {'reason': reason}));
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    if (o == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: _error != null
            ? ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: _load)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('Pedido #${o.code}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [StatusChip(o.status), const Spacer(), Text(dateTime(o.createdAt), style: t.bodySmall)]),
          const SizedBox(height: 12),
          if (o.customer != null) _CustomerCard(customer: o.customer!, code: o.code),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final i in o.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      SizedBox(width: 52, height: 52, child: ProductImage(url: i.thumbUrl, radius: 8)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i.productName, maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text('${i.variant} · ${i.quantity} × ${money(i.unitPrice)}', style: t.bodySmall),
                        ]),
                      ),
                      Text(money(i.total)),
                    ]),
                  ),
                const Divider(),
                _line('Produtos', money(o.subtotal)),
                if (o.discount > 0) _line('Você economizou', money(o.discount)),
                if (o.delivery) _line('Entrega', o.deliveryFee == 0 ? 'Grátis' : money(o.deliveryFee)),
                _line('Total', money(o.total), bold: true),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.delivery ? 'Entrega' : 'Retirada na loja', style: t.titleSmall),
                if (o.address != null) Text(o.address!),
                const SizedBox(height: 8),
                Text('Pagamento: ${paymentLabels[o.paymentMethod] ?? o.paymentMethod} · ${o.paid ? 'pago' : 'a pagar'}'),
                if (o.notes != null) ...[const SizedBox(height: 8), Text('Obs.: ${o.notes}')],
                if (o.cancelReason != null) ...[
                  const SizedBox(height: 8),
                  Text('Cancelado: ${o.cancelReason}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('Acompanhamento', style: t.titleSmall),
          const SizedBox(height: 8),
          for (final e in o.events)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.status == OrderStatus.canceled ? Icons.cancel_rounded : Icons.check_circle_rounded,
                  color: e.status == OrderStatus.canceled ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
              title: Text(e.status.label),
              subtitle: Text([dateTime(e.createdAt), if (e.byCustomer && widget.team) 'pelo cliente', ?e.note].join(' · ')),
            ),
          const SizedBox(height: 80),
        ]),
      ),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: _actions(o))),
    );
  }

  Widget _actions(Order o) {
    if (_busy) return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
    if (!widget.team) {
      return o.canCancel
          ? OutlinedButton(onPressed: _cancelMine, child: const Text('Cancelar pedido'))
          : const SizedBox.shrink();
    }
    final forward = o.nextStatuses.where((s) => s != OrderStatus.canceled).toList();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        for (final s in forward)
          Expanded(
            child: FilledButton(
              onPressed: () => _changeStatus(s),
              child: Text(switch (s) {
                OrderStatus.confirmed => 'Confirmar',
                OrderStatus.ready => 'Pronto p/ retirar',
                OrderStatus.shipped => 'Saiu p/ entrega',
                OrderStatus.delivered => 'Entregue',
                _ => s.label,
              }),
            ),
          ),
      ]),
      if (o.status != OrderStatus.canceled) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _act(() => widget.api.post('/api/store/orders/${o.id}/paid', {'paid': !o.paid})),
              icon: Icon(o.paid ? Icons.money_off_rounded : Icons.payments_rounded),
              label: Text(o.paid ? 'Desmarcar pago' : 'Marcar pago'),
            ),
          ),
          if (o.nextStatuses.contains(OrderStatus.canceled)) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(onPressed: () => _changeStatus(OrderStatus.canceled), child: const Text('Cancelar')),
            ),
          ],
        ]),
      ],
    ]);
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
          const Spacer(),
          Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
        ]),
      );
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.code});

  final Customer customer;
  final String code;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.person_rounded),
            title: Text(customer.name),
            subtitle: Text([customer.phone, customer.email].whereType<String>().join(' · ')),
            trailing: customer.phone == null
                ? null
                : IconButton(
                    tooltip: 'WhatsApp',
                    icon: const Icon(Icons.chat_rounded),
                    onPressed: () => launchUrl(whatsappUri(customer.phone!, 'Olá, ${customer.name.split(' ').first}! Sobre o pedido #$code da Loja Max:'),
                        mode: LaunchMode.externalApplication),
                  ),
          ),
        ),
      );
}
