import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import 'product_screen.dart';

/// Vitrine de uma loja: departamentos (roupas, calçados, bijuterias), categorias, busca e promoções.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.api, required this.slug, required this.storeName, this.onSwitchStore});

  final ApiClient api;
  final String slug;
  final String storeName;

  /// Trocar de loja (nulo no app de uma loja só).
  final VoidCallback? onSwitchStore;

  String get base => '/api/public/stores/$slug';

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
  StoreInfo? _info;

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
      final cats = await widget.api.get('${widget.base}/categories') as List;
      final promos = await widget.api.get('${widget.base}/promotions') as List;
      final info = StoreInfo.fromJson(await widget.api.get(widget.base) as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _info = info;
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
      final json = await widget.api.get('${widget.base}/products?${Uri(queryParameters: query).query}') as Map<String, dynamic>;
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
        title: InkWell(
          onTap: widget.onSwitchStore,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(widget.storeName.isEmpty ? 'Loja Max' : widget.storeName, overflow: TextOverflow.ellipsis)),
            if (widget.onSwitchStore != null) const Icon(Icons.expand_more_rounded),
          ]),
        ),
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
          if (_info != null) SliverToBoxAdapter(child: _StoreHeader(info: _info!)),
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
                            MaterialPageRoute(builder: (_) => ProductScreen(api: widget.api, slug: widget.slug, productId: p.productId!)));
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
                      context, MaterialPageRoute(builder: (_) => ProductScreen(api: widget.api, slug: widget.slug, productId: _items[i].id))),
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

/// Capa, logo, descrição, "aberta agora" e horários da loja (os horários abrem ao tocar).
class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.info});

  final StoreInfo info;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (info.coverUrl != null)
        SizedBox(height: 120, width: double.infinity, child: ProductImage(url: info.coverUrl, radius: 0))
      else
        Container(
          height: 56,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.brand, AppTheme.sale])),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StoreLogo(name: info.name, url: info.logoUrl, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(info.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              OpenBadge(info.status),
              if (info.description != null)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(info.description!, style: t.bodySmall)),
            ]),
          ),
          if (info.hours.isNotEmpty)
            IconButton(
              tooltip: 'Horários',
              icon: Icon(Icons.schedule_rounded, color: scheme.primary),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Horário de funcionamento', style: t.titleMedium),
                    const SizedBox(height: 12),
                    for (final line in info.hours) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(line)),
                    if (info.pickupAddress != null) ...[
                      const SizedBox(height: 12),
                      Text('Retirada: ${info.pickupAddress}', style: t.bodySmall),
                    ],
                  ]),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}
