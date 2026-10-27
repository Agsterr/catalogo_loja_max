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
                      ProductTile(product: _items[i], showStock: true, onTap: () => _openForm(_items[i].id)),
                ),
              ),
            ),
    );
  }
}
