import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../cart.dart';

/// Produto: fotos (com zoom e da cor escolhida), preço com promoção, cor e tamanho com estoque, tabela de medidas,
/// compartilhar, carrinho e "avise-me quando chegar".
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.api, required this.slug, required this.productId});

  final ApiClient api;
  final String slug;
  final int productId;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Product? _product;
  Object? _error;
  String? _color;
  Variant? _selected;
  int _quantity = 1;
  int _photo = 0;
  bool _watching = false;
  final _pages = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = Product.fromJson(
          await widget.api.get('/api/public/stores/${widget.slug}/products/${widget.productId}') as Map<String, dynamic>);
      if (!mounted) return;
      final available = p.variants.where((v) => v.active && v.stock > 0).toList();
      final colors = _colorsOf(p);
      setState(() {
        _product = p;
        // uma cor só (ou nenhuma): já vem escolhida; senão a pessoa escolhe
        _color = colors.length <= 1 ? (colors.isEmpty ? null : colors.first) : null;
        _selected = available.length == 1 ? available.first : null;
        if (_selected != null && _selected!.color.isNotEmpty) _color = _selected!.color;
      });
      _loadWatch();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Cores em ordem de cadastro (sem repetir; vazio = produto sem cor, como bijuteria).
  static List<String> _colorsOf(Product p) {
    final out = <String>[];
    for (final v in p.variants.where((v) => v.active)) {
      if (v.color.isNotEmpty && !out.contains(v.color)) out.add(v.color);
    }
    return out;
  }

  /// Fotos para mostrar: as da cor escolhida (mais as de todas as cores) primeiro; sem cor escolhida, todas.
  List<Photo> _photosFor(Product p) {
    final c = _color;
    if (c == null) return p.photos;
    final match = p.photos.where((f) => f.color == c).toList();
    if (match.isEmpty) return p.photos;
    return [...match, ...p.photos.where((f) => f.color == null)];
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
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => LoginScreen(session: session)));
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

  void _share(Product p) {
    final store = AppScope.of(context).store.store?.name;
    final b = StringBuffer('${p.name}${store != null && store.isNotEmpty ? ' — $store' : ''}\n');
    b.write(p.onSale ? 'De ${money(p.price)} por ${money(p.finalPrice)} (${p.discountPercent}% off)' : money(p.price));
    b.write('\nVeja no app Loja Max: ${AppConfig.siteUrl}/l/${widget.slug}/p/${p.id}');
    SharePlus.instance.share(ShareParams(text: b.toString(), subject: p.name));
  }

  /// Escolhe o tamanho dentro da cor escolhida.
  void _pickSize(Variant v) => setState(() {
        _selected = v;
        _quantity = _quantity.clamp(1, v.stock);
      });

  /// Trocar a cor desfaz o tamanho (o estoque é por cor e tamanho) e volta para a primeira foto.
  void _pickColor(String c) {
    setState(() {
      _color = c;
      if (_selected != null && _selected!.color != c) _selected = null;
      _photo = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  Future<void> _addToCart(Cart cart) async {
    final p = _product!;
    final v = _selected;
    if (v == null) {
      showInfo(context, _colorsOf(p).length > 1 && _color == null ? 'Escolha a cor e o tamanho.' : 'Escolha o tamanho.');
      return;
    }
    if (cart.fromOtherStore(widget.slug) &&
        !await confirm(context, 'Trocar o carrinho?', 'Seu carrinho tem peças de outra loja. Cada pedido é de uma loja só.',
            ok: 'Trocar')) {
      return;
    }
    if (!mounted) return;
    final photos = _photosFor(p);
    cart.add(
      store: widget.slug,
      CartItem(
        variantId: v.id,
        productId: p.id,
        name: p.name,
        variant: v.label,
        unitPrice: p.finalPrice,
        quantity: _quantity,
        thumbUrl: photos.isEmpty ? null : photos.first.thumbUrl,
        maxStock: v.stock,
      ),
    );
    showInfo(context, 'Adicionado ao carrinho.');
  }

  void _zoom(List<Photo> photos, int index) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _PhotoViewer(photos: photos, initial: index)));
  }

  void _showSizeChart(Product p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tabela de medidas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(p.sizeChart!),
          ]),
        ),
      ),
    );
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
    final colors = _colorsOf(p);
    final photos = _photosFor(p);
    // tamanhos da cor escolhida (sem cor cadastrada: todos); com várias cores e nenhuma escolhida, pede a cor primeiro
    final needsColor = colors.length > 1 && _color == null;
    final sizes = needsColor ? <Variant>[] : variants.where((v) => colors.isEmpty || v.color == _color).toList();
    final onlyOneSize = colors.isEmpty && variants.length == 1 && variants.first.size.toLowerCase() == 'único';
    return Scaffold(
      appBar: AppBar(title: Text(p.department.label), actions: [
        IconButton(tooltip: 'Compartilhar', icon: const Icon(Icons.ios_share_rounded), onPressed: () => _share(p)),
      ]),
      body: ListView(children: [
        AspectRatio(
          aspectRatio: 1,
          child: photos.isEmpty
              ? const ProductImage(radius: 0)
              : Stack(children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _photo = i),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _zoom(photos, i),
                      child: ProductImage(url: photos[i].url, radius: 0),
                    ),
                  ),
                  const Positioned(
                    right: 12,
                    top: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 18)),
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (var i = 0; i < photos.length; i++)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: i == _photo ? Colors.white : Colors.white54),
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
            if (colors.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(_color == null ? 'Cor' : 'Cor: $_color', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in colors)
                  ColorDot(
                    name: c,
                    selected: _color == c,
                    // cor sem nenhum tamanho em estoque fica apagada (mas dá para ver)
                    dimmed: variants.where((v) => v.color == c).every((v) => v.stock == 0),
                    onTap: () => _pickColor(c),
                  ),
              ]),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Text(onlyOneSize ? 'Disponibilidade' : 'Tamanho', style: t.titleSmall),
              const Spacer(),
              if (p.sizeChart != null)
                TextButton.icon(
                  onPressed: () => _showSizeChart(p),
                  icon: const Icon(Icons.straighten_rounded, size: 18),
                  label: const Text('Tabela de medidas'),
                ),
            ]),
            const SizedBox(height: 8),
            if (needsColor)
              Text('Escolha a cor para ver os tamanhos.', style: t.bodyMedium)
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in sizes)
                  ChoiceChip(
                    label: Text(v.size),
                    selected: _selected?.id == v.id,
                    onSelected: v.stock == 0 ? null : (_) => _pickSize(v),
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
                  onPressed: _quantity < (_selected?.stock ?? 1).clamp(1, Cart.maxPerItem) ? () => setState(() => _quantity++) : null,
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

/// Foto em tela cheia: pinça para dar zoom, arrasta para ver os detalhes e passa para as outras fotos.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initial});

  final List<Photo> photos;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.photos.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: networkImage(widget.photos[i].url, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
