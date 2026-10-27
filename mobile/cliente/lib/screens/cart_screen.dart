import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';
import '../cart.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

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
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: cart.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _CartLine(item: cart.items[i], cart: cart),
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
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _fee {
    final s = _store;
    if (s == null || !_delivery) return 0;
    if (s.freeDeliveryFrom != null && widget.cart.subtotal >= s.freeDeliveryFrom!) return 0;
    return s.deliveryFee;
  }

  Future<void> _place() async {
    if (_delivery && _address.text.trim().length < 10) {
      showInfo(context, 'Informe o endereço completo para a entrega.');
      return;
    }
    setState(() => _busy = true);
    try {
      final slug = widget.cart.storeSlug!;
      final json = await widget.api.post('/api/stores/$slug/orders', {
        'items': [for (final i in widget.cart.items) {'variantId': i.variantId, 'quantity': i.quantity}],
        'deliveryMethod': _delivery ? 'DELIVERY' : 'PICKUP',
        'paymentMethod': _payment,
        if (_delivery) 'address': _address.text.trim(),
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
                if (_delivery)
                  TextField(
                    controller: _address,
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 400,
                    decoration: const InputDecoration(labelText: 'Endereço (rua, número, bairro, complemento)'),
                  ),
                const SizedBox(height: 12),
                Text('Pagamento (na retirada/entrega)', style: t.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [for (final e in paymentLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                  selected: {_payment},
                  onSelectionChanged: (v) => setState(() => _payment = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Observação (opcional)'),
                ),
                const SizedBox(height: 8),
                _row('Produtos', money(widget.cart.subtotal)),
                if (_delivery) _row('Entrega', _fee == 0 ? 'Grátis' : money(_fee)),
                _row('Total estimado', money(widget.cart.subtotal + _fee), bold: true),
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
