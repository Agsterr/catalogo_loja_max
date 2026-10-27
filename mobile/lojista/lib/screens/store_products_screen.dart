import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import 'product_form_screen.dart';

/// Produtos da loja (inclusive os ocultos), com estoque.
class StoreProductsScreen extends StatefulWidget {
  const StoreProductsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<StoreProductsScreen> createState() => _StoreProductsScreenState();
}

class _StoreProductsScreenState extends State<StoreProductsScreen> {
  Department? _department;
  String _q = '';
  final _items = <ProductCard>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _generation++;
    _items.clear();
    _page = 0;
    _hasMore = true;
    _loading = false;
    _error = null;
    await _more();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final query = {
        'page': '$_page',
        if (_department != null) 'department': _department!.api,
        if (_q.isNotEmpty) 'q': _q,
      };
      final page = PageResult.fromJson(
          await widget.api.get('/api/store/products?${Uri(queryParameters: query).query}') as Map<String, dynamic>,
          ProductCard.fromJson);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _page++;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  /// Segurar o produto: ajuste rápido do estoque de cada tamanho/cor, sem abrir o formulário.
  Future<void> _quickStock(ProductCard product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickStockSheet(api: widget.api, product: product),
    );
    _reload();
  }

  Future<void> _openForm([int? id]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(api: widget.api, productId: id)));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produtos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Buscar produto', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  _q = v.trim();
                  _reload();
                },
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
                ChoiceChip(
                  label: const Text('Tudo'),
                  selected: _department == null,
                  onSelected: (_) {
                    setState(() => _department = null);
                    _reload();
                  },
                ),
                for (final d in Department.values) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(d.label),
                    selected: _department == d,
                    onSelected: (_) {
                      setState(() => _department = d);
                      _reload();
                    },
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Produto'),
      ),
      body: _items.isEmpty
          ? (_error != null
              ? ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: _reload)
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : const EmptyState(icon: Icons.checkroom_outlined, text: 'Nenhum produto. Toque em + para cadastrar.'))
          : RefreshIndicator(
              onRefresh: _reload,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _more();
                  return false;
                },
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.58,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, i) =>
                      ProductTile(
                    product: _items[i],
                    showStock: true,
                    onTap: () => _openForm(_items[i].id),
                    onLongPress: () => _quickStock(_items[i]),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Entrada e baixa rápidas de estoque (−1, +1, +5) por tamanho/cor. Cada toque vira um lançamento no histórico.
class _QuickStockSheet extends StatefulWidget {
  const _QuickStockSheet({required this.api, required this.product});

  final ApiClient api;
  final ProductCard product;

  @override
  State<_QuickStockSheet> createState() => _QuickStockSheetState();
}

class _QuickStockSheetState extends State<_QuickStockSheet> {
  List<Variant>? _variants;
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/store/products/${widget.product.id}').then((j) {
      if (mounted) setState(() => _variants = Product.fromJson(j as Map<String, dynamic>).variants.where((v) => v.active).toList());
    }).catchError((Object e) {
      if (mounted) showError(context, e);
    });
  }

  Future<void> _move(Variant v, int delta) async {
    if (_busy.contains(v.id) || v.stock + delta < 0) return;
    setState(() => _busy.add(v.id));
    try {
      final json = await widget.api.post('/api/store/variants/${v.id}/stock',
          {'type': delta > 0 ? 'IN' : 'LOSS', 'quantity': delta.abs(), 'note': 'Ajuste rápido'}) as Map<String, dynamic>;
      final stock = json['stock'] as int;
      if (mounted) {
        setState(() => _variants = [
              for (final x in _variants!)
                x.id == v.id ? Variant(id: x.id, size: x.size, color: x.color, sku: x.sku, stock: stock, active: x.active) : x,
            ]);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(v.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final variants = _variants;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.product.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (variants == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else
          for (final v in variants)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(v.label),
              subtitle: Text(v.stock == 0 ? 'Esgotado' : '${v.stock} em estoque',
                  style: TextStyle(color: v.stock == 0 ? Theme.of(context).colorScheme.error : null)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton.outlined(onPressed: v.stock > 0 ? () => _move(v, -1) : null, icon: const Icon(Icons.remove_rounded)),
                const SizedBox(width: 4),
                IconButton.outlined(onPressed: () => _move(v, 1), icon: const Icon(Icons.add_rounded)),
                const SizedBox(width: 4),
                OutlinedButton(onPressed: () => _move(v, 5), child: const Text('+5')),
              ]),
            ),
        const SizedBox(height: 8),
        Text('Contagem e perdas: abra o produto.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
