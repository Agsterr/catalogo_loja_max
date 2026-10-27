import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';
import '../cart.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => CartScreenState();
}

class CartScreenState extends State<CartScreen> {
  /// O que mudou na última conferência com a loja (preço, estoque, peça que saiu de venda).
  List<String> _notes = const [];

  /// Confere o carrinho com a loja: o preço mostrado pode ser de quando a peça entrou (a promoção acabou, o estoque mudou).
  /// Chamado ao abrir a aba do carrinho e antes de fechar o pedido.
  Future<void> refresh() async {
    final scope = AppScope.of(context);
    final cart = scope.cart;
    final slug = cart.storeSlug;
    if (cart.isEmpty || slug == null) return;
    try {
      final json = await scope.session.api.post('/api/public/stores/$slug/cart/quote', {
        'items': [for (final i in cart.items) {'variantId': i.variantId, 'quantity': i.quantity}],
      }) as Map<String, dynamic>;
      final notes = cart.applyQuote((json['items'] as List).map((l) => QuoteLine.fromJson(l as Map<String, dynamic>)).toList());
      if (mounted) setState(() => _notes = notes);
    } catch (_) {
      // sem rede: segue com o que está no carrinho; a loja confere de novo ao fechar o pedido
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  Widget build(BuildContext context) {
    final cart = AppScope.of(context).cart;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(cart.isEmpty ? 'Carrinho' : 'Carrinho (${cart.count})')),
        // o carrinho é de uma loja só (a que estava aberta quando a peça entrou)
        body: cart.isEmpty
            ? const EmptyState(icon: Icons.shopping_bag_outlined, text: 'Seu carrinho está vazio.\nEscolha algo na vitrine!')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_notes.isNotEmpty)
                    Card(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.info_outline_rounded, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('A loja atualizou seu carrinho', style: TextStyle(fontWeight: FontWeight.w700))),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() => _notes = const []),
                            ),
                          ]),
                          for (final n in _notes) Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $n')),
                        ]),
                      ),
                    ),
                  for (final item in cart.items)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: _CartLine(item: item, cart: cart)),
                ],
              ),
        bottomNavigationBar: cart.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      const Text('Subtotal'),
                      const Spacer(),
                      Text(money(cart.subtotal), style: Theme.of(context).textTheme.titleMedium),
                    ]),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: () => _checkout(context), child: const Text('Fechar pedido')),
                  ]),
                ),
              ),
      ),
    );
  }

  Future<void> _checkout(BuildContext context) async {
    await refresh();
    if (!context.mounted || AppScope.of(context).cart.isEmpty || _notes.isNotEmpty) return; // mudou algo: revisar antes
    final session = AppScope.of(context).session;
    if (!session.signedIn) {
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => LoginScreen(session: AppScope.of(context).session)));
      if (ok != true || !context.mounted) return;
    }
    if (session.user?.isTeam ?? false) {
      showInfo(context, 'Entre com uma conta de cliente para comprar.');
      return;
    }
    final order = await showModalBottomSheet<Order>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CheckoutSheet(api: session.api, cart: AppScope.of(context).cart),
    );
    if (order != null && context.mounted) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => OrderScreen(api: session.api, orderId: order.id, slug: order.storeSlug)));
    }
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.item, required this.cart});

  final CartItem item;
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          SizedBox(width: 72, height: 72, child: ProductImage(url: item.thumbUrl)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(item.variant, style: t.bodySmall),
              Text(money(item.total), style: t.titleSmall),
            ]),
          ),
          Column(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => cart.setQuantity(item.variantId, item.quantity - 1),
                icon: Icon(item.quantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded),
              ),
              Text('${item.quantity}'),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: item.quantity < item.maxStock.clamp(1, Cart.maxPerItem)
                    ? () => cart.setQuantity(item.variantId, item.quantity + 1)
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
          ]),
        ]),
      ),
    );
  }
}

/// Retirada ou entrega, forma de pagamento e endereço. O total final é o calculado pela API.
class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({super.key, required this.api, required this.cart});

  final ApiClient api;
  final Cart cart;

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  StoreInfo? _store;
  bool _delivery = false;
  String _payment = 'PIX';
  final _address = TextEditingController();
  List<SavedAddress> _saved = const [];
  final _notes = TextEditingController();
  bool _busy = false;

  /// Loja que cobra por distância: posição do cliente e a taxa calculada pela loja.
  GeoPoint? _where;
  DeliveryQuote? _quote;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
    widget.api.get('/api/public/stores/${widget.cart.storeSlug}').then((j) {
      if (!mounted) return;
      final s = StoreInfo.fromJson(j as Map<String, dynamic>);
      setState(() {
        _store = s;
        _delivery = !s.pickupEnabled && s.deliveryEnabled;
      });
    }).catchError((Object e) {
      if (mounted) showError(context, e);
    });
  }

  /// Endereços salvos do cliente (valem em todas as lojas): o último já vem preenchido.
  Future<void> _loadAddresses() async {
    try {
      final list = (await widget.api.get('/api/me/addresses') as List).map((a) => SavedAddress.fromJson(a as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _saved = list;
        if (_address.text.isEmpty && list.isNotEmpty) _address.text = list.first.address;
      });
    } catch (_) {
      // sem endereços salvos: digita
    }
  }

  Future<void> _saveAddress() async {
    final label = TextEditingController(text: _saved.isEmpty ? 'Casa' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salvar endereço'),
        content: TextField(controller: label, maxLength: 40, decoration: const InputDecoration(labelText: 'Nome (Casa, Trabalho...)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    final name = label.text.trim();
    label.dispose();
    if (ok != true || name.isEmpty) return;
    try {
      await widget.api.post('/api/me/addresses', {'label': name, 'address': _address.text.trim()});
      await _loadAddresses();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteAddress(SavedAddress a) async {
    try {
      await widget.api.delete('/api/me/addresses/${a.id}');
      if (mounted) setState(() => _saved = _saved.where((x) => x.id != a.id).toList());
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Taxa pela distância: faixas da loja ou entregador da plataforma (o servidor calcula; precisa da localização).
  bool get _byDistance => _store != null && (_store!.courierDelivery || (_store!.deliveryZones.isNotEmpty && _store!.latitude != null));

  bool get _byCourier => _delivery && (_store?.courierDelivery ?? false);

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final p = await currentPosition();
      final q = await widget.api.get(
          '/api/public/stores/${widget.cart.storeSlug}/delivery-quote?lat=${p.lat}&lng=${p.lng}&subtotal=${widget.cart.subtotal}');
      if (mounted) {
        setState(() {
          _where = p;
          _quote = DeliveryQuote.fromJson(q as Map<String, dynamic>);
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  double get _fee {
    final s = _store;
    if (s == null || !_delivery) return 0;
    if (_byDistance) return _quote?.fee ?? 0;
    if (s.freeDeliveryFrom != null && widget.cart.subtotal >= s.freeDeliveryFrom!) return 0;
    return s.deliveryFee;
  }

  Future<void> _place() async {
    if (_delivery && _address.text.trim().length < 10) {
      showInfo(context, 'Informe o endereço completo para a entrega.');
      return;
    }
    if (_delivery && _byDistance && (_quote == null || !_quote!.available)) {
      showInfo(context, _quote?.message ?? 'Toque em "Calcular a entrega" para usar sua localização.');
      return;
    }
    setState(() => _busy = true);
    try {
      final slug = widget.cart.storeSlug!;
      final json = await widget.api.post('/api/stores/$slug/orders', {
        'items': [for (final i in widget.cart.items) {'variantId': i.variantId, 'quantity': i.quantity}],
        'deliveryMethod': _delivery ? 'DELIVERY' : 'PICKUP',
        'paymentMethod': _byCourier && _payment == 'CASH' ? 'PIX' : _payment,
        if (_delivery) 'address': _address.text.trim(),
        if (_delivery && _where != null) ...{'deliveryLat': _where!.lat, 'deliveryLng': _where!.lng},
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      }) as Map<String, dynamic>;
      widget.cart.clear();
      if (mounted) Navigator.pop(context, Order.fromJson(json, storeSlug: slug));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _store;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: s == null
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Como você quer receber?', style: t.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: const Text('Retirar na loja'), enabled: s.pickupEnabled),
                    ButtonSegment(value: true, label: const Text('Entrega'), enabled: s.deliveryEnabled),
                  ],
                  selected: {_delivery},
                  onSelectionChanged: (v) => setState(() => _delivery = v.first),
                ),
                const SizedBox(height: 8),
                if (!_delivery && s.pickupAddress != null) Text('Retirada em: ${s.pickupAddress}', style: t.bodySmall),
                if (_delivery) ...[
                  if (_saved.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final a in _saved)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InputChip(
                              avatar: const Icon(Icons.home_rounded, size: 18),
                              label: Text(a.label),
                              selected: _address.text == a.address,
                              onPressed: () => setState(() => _address.text = a.address),
                              onDeleted: () => _deleteAddress(a),
                            ),
                          ),
                      ]),
                    ),
                  TextField(
                    controller: _address,
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 400,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Endereço (rua, número, bairro, complemento)'),
                  ),
                  if (_address.text.trim().length >= 10 && !_saved.any((a) => a.address == _address.text.trim()))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saveAddress,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Salvar este endereço'),
                      ),
                    ),
                  if (_byDistance) ...[
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _locating ? null : _locate,
                      icon: _locating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded),
                      label: Text(_quote == null ? 'Calcular a entrega (usar minha localização)' : 'Recalcular com minha localização'),
                    ),
                    if (_quote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _quote!.available
                              ? 'Você está a ${_quote!.distanceKm?.toStringAsFixed(1).replaceAll('.', ',')} km da loja.'
                              : (_quote!.message ?? 'Fora da área de entrega.'),
                          style: t.bodySmall?.copyWith(color: _quote!.available ? null : Theme.of(context).colorScheme.error),
                        ),
                      ),
                    Text(
                        _byCourier
                            ? 'Entrega por entregador parceiro: a taxa vem da distância. Sua localização vai só para o entregador '
                                'achar o endereço.'
                            : 'Entregamos até ${kmLabel(s.deliveryZones.last.upToKm)}. A localização só calcula a taxa e não é guardada.',
                        style: t.bodySmall),
                  ],
                ],
                const SizedBox(height: 12),
                Text(_byCourier ? 'Pagamento dos produtos (antecipado)' : 'Pagamento (na retirada/entrega)', style: t.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    for (final e in paymentLabels.entries)
                      if (!(_byCourier && e.key == 'CASH')) ButtonSegment(value: e.key, label: Text(e.value)),
                  ],
                  selected: {_byCourier && _payment == 'CASH' ? 'PIX' : _payment},
                  onSelectionChanged: (v) => setState(() => _payment = v.first),
                ),
                if (_byCourier)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Os produtos são pagos à loja (ela combina com você). O entregador só sai depois que ela confirmar o pagamento e o pedido.',
                        style: t.bodySmall),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Observação (opcional)'),
                ),
                const SizedBox(height: 8),
                _row('Produtos', money(widget.cart.subtotal)),
                if (_delivery)
                  _row(_byCourier ? 'Frete (pago ao entregador)' : 'Entrega',
                      _byDistance && _quote == null ? 'a calcular' : (_fee == 0 ? 'Grátis' : money(_fee))),
                // entregador da plataforma: o frete vai direto ao entregador, então o total do pedido é só dos produtos
                _row(_byCourier ? 'Total dos produtos' : 'Total estimado', money(widget.cart.subtotal + (_byCourier ? 0 : _fee)),
                    bold: true),
                if (_byCourier && _quote != null && _quote!.available)
                  Text(
                      _fee == 0
                          ? 'Frete grátis: a loja paga o entregador.'
                          : 'Pague o frete de ${money(_fee)} direto ao entregador, na entrega (dinheiro ou Pix).',
                      style: t.bodySmall),
                Text('Os preços são conferidos pela loja na hora do pedido.', style: t.bodySmall),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _place,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Confirmar pedido'),
                ),
              ]),
            ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
          const Spacer(),
          Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
        ]),
      );
}
