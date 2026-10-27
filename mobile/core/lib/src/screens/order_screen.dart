import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../widgets.dart';

/// Pedido com itens, valores e linha do tempo. Com [team] mostra o cliente e as ações da loja
/// (confirmar, pronto/saiu para entrega, entregue, cancelar, pago).
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.api, required this.orderId, this.team = false, this.slug});

  final ApiClient api;
  final int orderId;
  final bool team;

  /// Loja do pedido (cliente); a equipe usa a loja do login.
  final String? slug;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Order? _order;
  Object? _error;
  bool _busy = false;

  String get _path => widget.team ? '/api/store/orders/${widget.orderId}' : '/api/stores/${widget.slug}/orders/${widget.orderId}';

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
    await _act(() => widget.api.post('$_path/cancel', {'reason': reason}));
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
      appBar: AppBar(title: Text('Pedido #${o.code}'), actions: [
        IconButton(
          tooltip: widget.team ? 'Compartilhar / imprimir comprovante' : 'Compartilhar pedido',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => SharePlus.instance.share(ShareParams(text: receipt(o), subject: 'Pedido #${o.code}')),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [StatusChip(o.status), const Spacer(), Text(dateTime(o.createdAt), style: t.bodySmall)]),
          const SizedBox(height: 12),
          if (o.customer != null) _CustomerCard(customer: o.customer!, code: o.code, status: o.status),
          if (o.courier != null)
            _CourierCard(
              api: widget.api,
              info: o.courier!,
              team: widget.team,
              path: _path,
              orderId: o.id,
              onChanged: _load,
            ),
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
                if (o.discount > 0) _line(widget.team ? 'Descontos' : 'Você economizou', money(o.discount)),
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
  const _CustomerCard({required this.customer, required this.code, required this.status});

  final Customer customer;
  final String code;
  final OrderStatus status;

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
                    onPressed: () => launchUrl(whatsappUri(customer.phone!, statusMessage(customer.name, code, status)),
                        mode: LaunchMode.externalApplication),
                  ),
          ),
        ),
      );
}

/// Comprovante em texto (vai para o WhatsApp, e-mail ou impressora pelo menu de compartilhar do celular).
String receipt(Order o) {
  final b = StringBuffer()
    ..writeln('*Pedido #${o.code}* — ${dateTime(o.createdAt)}')
    ..writeln('Status: ${o.status.label}')
    ..writeln();
  if (o.customer != null) {
    b.writeln('Cliente: ${o.customer!.name}${o.customer!.phone != null ? ' · ${o.customer!.phone}' : ''}');
  }
  b.writeln(o.delivery ? 'Entrega${o.address != null ? ': ${o.address}' : ''}' : 'Retirada na loja');
  b.writeln();
  for (final i in o.items) {
    b.writeln('${i.quantity}x ${i.productName} (${i.variant}) — ${money(i.total)}');
  }
  b.writeln();
  if (o.discount > 0) b.writeln('Desconto: ${money(o.discount)}');
  if (o.delivery) b.writeln('Entrega: ${o.deliveryFee == 0 ? 'grátis' : money(o.deliveryFee)}');
  b.writeln('*Total: ${money(o.total)}*');
  b.writeln('Pagamento: ${paymentLabels[o.paymentMethod] ?? o.paymentMethod} · ${o.paid ? 'pago' : 'a pagar'}');
  if (o.notes != null) b.writeln('Obs.: ${o.notes}');
  return b.toString().trim();
}

/// Mensagem pronta para o cliente, conforme o andamento do pedido.
String statusMessage(String name, String code, OrderStatus status) {
  final first = name.split(' ').first;
  final what = switch (status) {
    OrderStatus.pending => 'recebemos o seu pedido e já vamos separar as peças.',
    OrderStatus.confirmed => 'o seu pedido foi confirmado e estamos separando as peças.',
    OrderStatus.ready => 'o seu pedido está pronto para retirada!',
    OrderStatus.shipped => 'o seu pedido saiu para entrega.',
    OrderStatus.delivered => 'obrigado pela compra! Qualquer dúvida é só chamar.',
    OrderStatus.canceled => 'precisamos cancelar o seu pedido. Podemos conversar?',
  };
  return 'Olá, $first! Pedido #$code: $what';
}


/// Entrega por entregador da plataforma: situação da corrida, o código certo para cada lado (a loja vê o de coleta; o cliente,
/// o de entrega), o frete, onde o entregador está agora, o bônus (loja) e a avaliação (cliente).
class _CourierCard extends StatefulWidget {
  const _CourierCard({
    required this.api,
    required this.info,
    required this.team,
    required this.path,
    required this.orderId,
    required this.onChanged,
  });

  final ApiClient api;
  final CourierInfo info;
  final bool team;

  /// Caminho do pedido na API (`/api/store/orders/1` ou `/api/stores/slug/orders/1`).
  final String path;
  final int orderId;
  final Future<void> Function() onChanged;

  @override
  State<_CourierCard> createState() => _CourierCardState();
}

class _CourierCardState extends State<_CourierCard> {
  Tracking? _tracking;
  Timer? _timer;
  bool _busy = false;

  CourierInfo get info => widget.info;

  @override
  void initState() {
    super.initState();
    _syncTracking();
  }

  @override
  void didUpdateWidget(covariant _CourierCard old) {
    super.didUpdateWidget(old);
    if (old.info.status != info.status) _syncTracking();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Enquanto a corrida está ativa, atualiza a posição a cada 15 s (a tela fechada não consulta).
  void _syncTracking() {
    _timer?.cancel();
    if (!info.tracking) {
      _tracking = null;
      return;
    }
    _loadTracking();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _loadTracking());
  }

  Future<void> _loadTracking() async {
    try {
      final j = await widget.api.get('${widget.path}/tracking') as Map<String, dynamic>;
      if (mounted) setState(() => _tracking = Tracking.fromJson(j));
    } catch (_) {
      // sem sinal agora: mantém a última posição
    }
  }

  Future<void> _retry() async {
    final bonus = await showDialog<double>(context: context, builder: (_) => _BonusDialog(current: info.bonus, open: info.status == 'OPEN'));
    if (bonus == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.post('/api/store/orders/${widget.orderId}/courier/retry', {'bonus': bonus});
      await widget.onChanged();
      if (mounted) showInfo(context, 'Entregadores da região avisados de novo.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rate() async {
    final result = await showDialog<({int stars, String comment})>(context: context, builder: (_) => const _RateDialog());
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.post('${widget.path}/rate-courier', {'stars': result.stars, if (result.comment.isNotEmpty) 'comment': result.comment});
      await widget.onChanged();
      if (mounted) showInfo(context, 'Obrigado pela avaliação!');
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
    final team = widget.team;
    final code = team ? info.pickupCode : info.deliveryCode;
    final tr = _tracking;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.two_wheeler_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(child: Text('Entregador da plataforma', style: t.titleSmall)),
          ]),
          const SizedBox(height: 6),
          Text(info.statusLabel, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (tr != null && tr.active) _trackingLine(context, tr),
          if (info.freight != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                  info.freightPayer == 'STORE'
                      ? (team
                          ? 'Frete de ${money(info.freight!)}: por conta da loja, pago ao entregador na coleta.'
                          : 'Frete grátis: a loja paga o entregador.')
                      : (team
                          ? 'Frete de ${money(info.freight!)}: o cliente paga ao entregador na entrega.'
                          : 'Frete de ${money(info.freight!)}: pague ao entregador na entrega (dinheiro ou Pix).'),
                  style: t.bodySmall),
            ),
          if (team && info.bonus > 0)
            Text('Bônus de ${money(info.bonus)}: por sua conta, pago ao entregador na coleta.', style: t.bodySmall),
          if (info.courierName != null)
            Text([info.courierName!, ?info.vehicle].join(' · '), style: t.bodyMedium),
          if (info.courierRating != null)
            Text('★ ${info.courierRating!.toStringAsFixed(1).replaceAll('.', ',')} (${info.courierRatings} avaliações)', style: t.bodySmall),
          if (info.courierPhone != null)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: info.courierPhone)),
              icon: const Icon(Icons.call_rounded, size: 18),
              label: Text(info.courierPhone!),
            ),
          if (code != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text(team ? 'Código de coleta' : 'Código de entrega', style: t.bodySmall),
                Text(code, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6)),
              ]),
            ),
            const SizedBox(height: 6),
            Text(
                team
                    ? 'Passe este código ao entregador só quando ele chegar para retirar o pedido.'
                    : 'Diga este código ao entregador só quando receber o pedido. Ele confirma a entrega com ele.',
                style: t.bodySmall),
          ],
          if (info.status == 'OPEN' && info.expiresAt != null) ...[
            const SizedBox(height: 4),
            Text('Os entregadores da região já foram avisados.', style: t.bodySmall),
          ],
          if (team && (info.canRetry || info.status == 'OPEN')) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _retry,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: Text(info.canRetry ? 'Chamar de novo (com bônus)' : 'Aumentar o bônus'),
            ),
          ],
          if (!team && info.canRate) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _rate,
              icon: const Icon(Icons.star_rounded),
              label: const Text('Avaliar o entregador'),
            ),
          ],
          if (!team && info.rated) Text('Você avaliou este entregador. Obrigado!', style: t.bodySmall),
        ]),
      ),
    );
  }

  Widget _trackingLine(BuildContext context, Tracking tr) {
    final t = Theme.of(context).textTheme;
    final where = tr.target == 'LOJA' ? 'da loja' : (widget.team ? 'do cliente' : 'de você');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Expanded(
          child: Text(
              tr.lat == null
                  ? 'Aguardando a posição do entregador...'
                  : [
                      if (tr.distanceKm != null) 'A ${tr.distanceKm!.toStringAsFixed(1).replaceAll('.', ',')} km $where',
                      if (tr.etaMinutes != null) 'chega em ~${tr.etaMinutes} min',
                      if (tr.stale) '(posição antiga)',
                    ].join(' · '),
              style: t.bodyMedium),
        ),
        if (tr.lat != null)
          TextButton(
            onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${tr.lat},${tr.lng}'),
                mode: LaunchMode.externalApplication),
            child: const Text('Ver no mapa'),
          ),
      ]),
    );
  }
}

/// Bônus que a loja soma ao frete para um entregador aceitar mais rápido (pago por ela, direto ao entregador, na coleta).
class _BonusDialog extends StatefulWidget {
  const _BonusDialog({required this.current, required this.open});

  final double current;

  /// A corrida já está no mural: só dá para aumentar.
  final bool open;

  @override
  State<_BonusDialog> createState() => _BonusDialogState();
}

class _BonusDialogState extends State<_BonusDialog> {
  late double _bonus = widget.open ? widget.current + 2 : widget.current;
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = [0.0, 3.0, 5.0, 10.0, 15.0].where((v) => !widget.open || v > widget.current).toList();
    return AlertDialog(
      title: Text(widget.open ? 'Aumentar o bônus' : 'Chamar entregador de novo'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('O bônus é somado ao frete e você paga direto ao entregador, na coleta. Ele aparece no mural e no aviso.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final v in options)
            ChoiceChip(
              label: Text(v == 0 ? 'Sem bônus' : money(v)),
              selected: _bonus == v && _custom.text.isEmpty,
              onSelected: (_) => setState(() {
                _bonus = v;
                _custom.clear();
              }),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _custom,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Outro valor (até R\$ 50)', prefixText: 'R\$ '),
          onChanged: (v) => setState(() => _bonus = double.tryParse(v.replaceAll(',', '.')) ?? _bonus),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(context, _bonus), child: const Text('Chamar')),
      ],
    );
  }
}

/// Estrelas (1 a 5) e um comentário opcional sobre o entregador.
class _RateDialog extends StatefulWidget {
  const _RateDialog();

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  int _stars = 5;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Como foi a entrega?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setState(() => _stars = i),
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 34, color: Colors.amber.shade700),
              ),
          ]),
          TextField(controller: _comment, maxLength: 300, maxLines: 2, decoration: const InputDecoration(labelText: 'Comentário (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(context, (stars: _stars, comment: _comment.text.trim())), child: const Text('Enviar')),
        ],
      );
}
