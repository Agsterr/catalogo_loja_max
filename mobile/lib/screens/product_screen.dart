import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../cart.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

/// Produto: fotos, preço (com promoção), tamanhos/cores com estoque, carrinho e "avise-me quando chegar".
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.api, required this.productId});

  final ApiClient api;
  final int productId;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Product? _product;
  Object? _error;
  Variant? _selected;
  int _quantity = 1;
  int _photo = 0;
  bool _watching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = Product.fromJson(await widget.api.get('/api/public/products/${widget.productId}') as Map<String, dynamic>);
      if (!mounted) return;
      final available = p.variants.where((v) => v.active && v.stock > 0).toList();
      setState(() {
        _product = p;
        _selected = available.length == 1 ? available.first : null;
      });
      _loadWatch();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadWatch() async {
    final session = AppScope.of(context).session;
    if (!session.signedIn) return;
    try {
      final ids = (await session.api.get('/api/me/watches') as List).cast<int>();
      if (mounted) setState(() => _watching = ids.contains(widget.productId));
    } catch (_) {}
  }

  Future<void> _toggleWatch() async {
    final session = AppScope.of(context).session;
    if (!session.signedIn) {
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      if (ok != true || !mounted) return;
    }
    try {
      if (_watching) {
        await session.api.delete('/api/me/watches/${widget.productId}');
      } else {
        await session.api.post('/api/me/watches/${widget.productId}');
      }
      if (!mounted) return;
      setState(() => _watching = !_watching);
      showInfo(context, _watching ? 'Combinado! Avisamos quando chegar.' : 'Aviso desligado.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _addToCart(Cart cart) {
    final p = _product!;
    final v = _selected;
    if (v == null) {
      showInfo(context, 'Escolha o tamanho.');
      return;
    }
    cart.add(CartItem(
      variantId: v.id,
      productId: p.id,
      name: p.name,
      variant: v.label,
      unitPrice: p.finalPrice,
      quantity: _quantity,
      thumbUrl: p.photos.isEmpty ? null : p.photos.first.thumbUrl,
      maxStock: v.stock,
    ));
    showInfo(context, 'Adicionado ao carrinho.');
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: _load)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final cart = AppScope.of(context).cart;
    final t = Theme.of(context).textTheme;
    final variants = p.variants.where((v) => v.active).toList();
    final soldOut = variants.every((v) => v.stock == 0);
    return Scaffold(
      appBar: AppBar(title: Text(p.department.label)),
      body: ListView(children: [
        AspectRatio(
          aspectRatio: 1,
          child: p.photos.isEmpty
              ? const ProductImage(radius: 0)
              : Stack(children: [
                  PageView.builder(
                    itemCount: p.photos.length,
                    onPageChanged: (i) => setState(() => _photo = i),
                    itemBuilder: (_, i) => ProductImage(url: p.photos[i].url, radius: 0),
                  ),
                  if (p.photos.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (var i = 0; i < p.photos.length; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _photo ? Colors.white : Colors.white54,
                            ),
                          ),
                      ]),
                    ),
                ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.brand != null) Text(p.brand!.toUpperCase(), style: t.labelMedium),
            Text(p.name, style: t.titleLarge),
            const SizedBox(height: 8),
            PriceTag(price: p.price, finalPrice: p.finalPrice, large: true),
            if (p.onSale)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${p.discountPercent}% off${p.promotion != null ? ' · ${p.promotion}' : ''}',
                  style: t.bodyMedium?.copyWith(color: AppTheme.sale, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 20),
            Text(variants.length == 1 && variants.first.size.toLowerCase() == 'único' ? 'Disponibilidade' : 'Tamanho',
                style: t.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in variants)
                ChoiceChip(
                  label: Text(v.label),
                  selected: _selected?.id == v.id,
                  onSelected: v.stock == 0
                      ? null
                      : (_) => setState(() {
                            _selected = v;
                            _quantity = _quantity.clamp(1, v.stock);
                          }),
                ),
            ]),
            if (_selected != null && _selected!.stock <= 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Só restam ${_selected!.stock}!', style: t.bodyMedium?.copyWith(color: AppTheme.sale)),
              ),
            const SizedBox(height: 16),
            if (!soldOut)
              Row(children: [
                IconButton.outlined(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('$_quantity', style: t.titleMedium)),
                IconButton.outlined(
                  onPressed: _quantity < (_selected?.stock ?? 1).clamp(1, Cart.maxPerItem)
                      ? () => setState(() => _quantity++)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
            if (p.description != null) ...[
              const SizedBox(height: 20),
              Text('Detalhes', style: t.titleSmall),
              const SizedBox(height: 4),
              Text(p.description!),
            ],
            if (p.categoryName != null) ...[
              const SizedBox(height: 12),
              Text('${p.department.label} › ${p.categoryName}', style: t.bodySmall),
            ],
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: soldOut
              ? FilledButton.tonalIcon(
                  onPressed: _toggleWatch,
                  icon: Icon(_watching ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
                  label: Text(_watching ? 'Vamos te avisar quando chegar' : 'Esgotado · Avise-me quando chegar'),
                )
              : FilledButton.icon(
                  onPressed: () => _addToCart(cart),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Adicionar ao carrinho'),
                ),
        ),
      ),
    );
  }
}
