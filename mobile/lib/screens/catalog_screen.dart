import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'product_screen.dart';

/// Vitrine: departamentos (roupas, calçados, bijuterias), categorias, busca e promoções.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  Department? _department;
  int? _categoryId;
  bool _onSale = false;
  String _sort = '';
  List<Category> _categories = const [];
  List<Promotion> _promotions = const [];

  final _items = <ProductCard>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _more();
    });
    _loadExtras();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadExtras() async {
    try {
      final cats = await widget.api.get('/api/public/categories') as List;
      final promos = await widget.api.get('/api/public/promotions') as List;
      if (!mounted) return;
      setState(() {
        _categories = cats.map((c) => Category.fromJson(c as Map<String, dynamic>)).toList();
        _promotions = promos.map((p) => Promotion.fromJson(p as Map<String, dynamic>)).toList();
      });
    } catch (_) {
      // sem categorias/promoções a vitrine funciona igual
    }
  }

  Future<void> _reload() async {
    _generation++;
    _items.clear();
    _page = 0;
    _hasMore = true;
    _error = null;
    _loading = false;
    await _more();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() => _loading = true);
    final query = {
      'page': '$_page',
      'size': '20',
      if (_department != null) 'department': _department!.api,
      if (_categoryId != null) 'categoryId': '$_categoryId',
      if (_onSale) 'onSale': 'true',
      if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      if (_sort.isNotEmpty) 'sort': _sort,
    };
    try {
      final json = await widget.api.get('/api/public/products?${Uri(queryParameters: query).query}') as Map<String, dynamic>;
      if (!mounted || generation != _generation) return;
      final page = PageResult.fromJson(json, ProductCard.fromJson);
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

  void _setDepartment(Department? d) {
    setState(() {
      _department = d;
      _categoryId = null;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categories.where((c) => _department != null && c.department == _department).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loja Max'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Ordenar',
            initialValue: _sort,
            onSelected: (v) {
              setState(() => _sort = v);
              _reload();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: '', child: Text('Novidades')),
              PopupMenuItem(value: 'menor-preco', child: Text('Menor preço')),
              PopupMenuItem(value: 'maior-preco', child: Text('Maior preço')),
              PopupMenuItem(value: 'nome', child: Text('Nome')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Buscar vestido, tênis, brinco…',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _reload);
              },
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadExtras();
          await _reload();
        },
        child: CustomScrollView(controller: _scroll, slivers: [
          if (_promotions.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 92,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  scrollDirection: Axis.horizontal,
                  itemCount: _promotions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _PromoBanner(
                    promotion: _promotions[i],
                    onTap: () {
                      final p = _promotions[i];
                      if (p.productId != null) {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ProductScreen(api: widget.api, productId: p.productId!)));
                        return;
                      }
                      setState(() {
                        _department = p.department;
                        _categoryId = p.categoryId;
                        _onSale = true;
                      });
                      _reload();
                    },
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(children: [
                ChoiceChip(label: const Text('Tudo'), selected: _department == null, onSelected: (_) => _setDepartment(null)),
                for (final d in Department.values) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(label: Text(d.label), selected: _department == d, onSelected: (_) => _setDepartment(d)),
                ],
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Promoções'),
                  avatar: const Icon(Icons.local_offer_rounded, size: 18),
                  selected: _onSale,
                  onSelected: (v) {
                    setState(() => _onSale = v);
                    _reload();
                  },
                ),
              ]),
            ),
          ),
          if (cats.isNotEmpty)
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  for (final c in cats) ...[
                    ChoiceChip(
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: (v) {
                        setState(() => _categoryId = v ? c.id : null);
                        _reload();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ]),
              ),
            ),
          if (_items.isEmpty && _error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: _reload),
            )
          else if (_items.isEmpty && _loading)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.search_off_rounded, text: 'Nenhum produto encontrado.'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                itemCount: _items.length,
                itemBuilder: (context, i) => ProductTile(
                  product: _items[i],
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ProductScreen(api: widget.api, productId: _items[i].id))),
                ),
              ),
            ),
          if (_items.isNotEmpty && _hasMore)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))),
        ]),
      ),
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.promotion, required this.onTap});

  final Promotion promotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [AppTheme.brand, AppTheme.sale]),
        ),
        child: Row(children: [
          Text('-${promotion.discountPercent}%',
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(promotion.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              Text(promotion.scope, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Cartão do produto na grade (vitrine e gestão).
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap, this.showStock = false});

  final ProductCard product;
  final VoidCallback onTap;
  final bool showStock;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            ProductImage(url: product.thumbUrl),
            if (product.discountPercent > 0)
              Positioned(
                left: 8,
                top: 8,
                child: _Badge(text: '-${product.discountPercent}%', color: AppTheme.sale),
              ),
            if (!product.inStock)
              const Positioned(right: 8, top: 8, child: _Badge(text: 'Esgotado', color: Colors.black87)),
            if (showStock && !product.active)
              const Positioned(right: 8, bottom: 8, child: _Badge(text: 'Oculto', color: Colors.black54)),
          ]),
        ),
        const SizedBox(height: 6),
        Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
        if (showStock) Text('${product.totalStock} em estoque', style: t.bodySmall),
        PriceTag(price: product.price, finalPrice: product.finalPrice),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
