import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'format.dart';
import 'models.dart';
import 'theme.dart';

/// Mensagem de erro curta embaixo da tela.
void showError(BuildContext context, Object error) {
  final text = error is ApiException ? error.message : 'Algo deu errado. Tente de novo.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

void showInfo(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Tentar de novo')),
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Foto do produto (R2), guardada em disco: a vitrine abre mais rápido e gasta menos internet. Fundo neutro
/// enquanto carrega ou quando não tem.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, this.url, this.fit = BoxFit.cover, this.radius = 12});

  final String? url;
  final BoxFit fit;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    final placeholder = Container(
      color: color,
      alignment: Alignment.center,
      child: Icon(Icons.checkroom_rounded, color: Theme.of(context).colorScheme.outline),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder
          : networkImage(url!, fit: fit, placeholder: placeholder),
    );
  }
}

/// Foto da internet com cache em disco. Os testes que desenham telas (`mobile/telas`) trocam por [Image.network],
/// porque o cache precisa de plugins que não existem no `flutter test`.
@visibleForTesting
bool networkImageWithoutCache = false;

Widget networkImage(String url, {BoxFit fit = BoxFit.cover, Widget? placeholder}) {
  if (networkImageWithoutCache) {
    return Image.network(url, fit: fit, errorBuilder: (_, _, _) => placeholder ?? const SizedBox.shrink());
  }
  return CachedNetworkImage(
    imageUrl: url,
    fit: fit,
    fadeInDuration: const Duration(milliseconds: 120),
    placeholder: placeholder == null ? null : (_, _) => placeholder,
    errorWidget: (_, _, _) => placeholder ?? const SizedBox.shrink(),
  );
}

/// Preço com "de/por" quando está em promoção.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.price, required this.finalPrice, this.large = false});

  final double price;
  final double finalPrice;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final main = (large ? t.headlineSmall : t.titleMedium)?.copyWith(fontWeight: FontWeight.w700);
    if (finalPrice >= price) return Text(money(price), style: main);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
      Text(money(finalPrice), style: main?.copyWith(color: AppTheme.sale)),
      Text(money(price),
          style: t.bodySmall?.copyWith(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.outline)),
    ]);
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = switch (status) {
      // âmbar: chama atenção para o que a loja ainda precisa confirmar
      OrderStatus.pending => dark ? (const Color(0xFF4A3300), const Color(0xFFFFDDB0)) : (const Color(0xFFFFE8C2), const Color(0xFF7A4A00)),
      OrderStatus.canceled => (scheme.errorContainer, scheme.onErrorContainer),
      OrderStatus.delivered => (scheme.surfaceContainerHighest, scheme.onSurface),
      _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Lista paginada com rolagem infinita (as listas da API vêm em páginas de 20).
class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.load,
    required this.itemBuilder,
    required this.empty,
    this.padding = const EdgeInsets.all(12),
    this.separator = const SizedBox(height: 8),
  });

  final Future<PageResult<T>> Function(int page) load;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget empty;
  final EdgeInsets padding;
  final Widget separator;

  @override
  State<PagedList<T>> createState() => PagedListState<T>();
}

class PagedListState<T> extends State<PagedList<T>> {
  final _items = <T>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    _items.clear();
    _page = 0;
    _hasMore = true;
    _error = null;
    await _more();
  }

  Future<void> _more() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final result = await widget.load(_page);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _hasMore = result.hasMore;
        _page++;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _error != null) {
      return ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: refresh);
    }
    if (_items.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return RefreshIndicator(onRefresh: refresh, child: ListView(children: [const SizedBox(height: 80), widget.empty]));
    return RefreshIndicator(
      onRefresh: refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) _more();
          return false;
        },
        child: ListView.separated(
          padding: widget.padding,
          itemCount: _items.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => widget.separator,
          itemBuilder: (context, i) => i < _items.length
              ? widget.itemBuilder(context, _items[i])
              : const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ),
      ),
    );
  }
}

/// Pede confirmação antes de uma ação séria.
Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirmar'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// Cartão do produto na grade (vitrine e gestão).
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap, this.onLongPress, this.showStock = false});

  final ProductCard product;
  final VoidCallback onTap;

  /// Segurar o produto (gestão: ajuste rápido de estoque).
  final VoidCallback? onLongPress;
  final bool showStock;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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

/// Pedido nas listas (cliente e gestão).
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.onTap, this.showCustomer = false});

  final OrderSummary order;
  final VoidCallback onTap;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            SizedBox(width: 60, height: 60, child: ProductImage(url: order.thumbUrl, radius: 10)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${order.code}${showCustomer ? ' · ${order.customerName}' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                Text(
                  '${order.itemCount == 1 ? '1 item' : '${order.itemCount} itens'} · ${money(order.total)}'
                  '${order.delivery ? ' · entrega' : ' · retirada'}${order.paid ? ' · pago' : ''}',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusChip(order.status),
                  Text(ago(order.createdAt), style: t.bodySmall),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

/// Selo "Aberta agora" / "Fechada" da loja.
class OpenBadge extends StatelessWidget {
  const OpenBadge(this.status, {super.key});

  final OpenStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();
    final color = s.open ? const Color(0xFF1B7F3B) : Theme.of(context).colorScheme.outline;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 9, color: color),
      const SizedBox(width: 5),
      Flexible(
        child: Text(s.label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// Logo da loja (ou a inicial do nome).
class StoreLogo extends StatelessWidget {
  const StoreLogo({super.key, required this.name, this.url, this.size = 44});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: url != null
          ? ClipOval(child: networkImage(url!, fit: BoxFit.cover, placeholder: _initial(scheme)))
          : _initial(scheme),
    );
  }

  Widget _initial(ColorScheme scheme) => CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
      );
}

/// Cor da bolinha para o nome da cor cadastrada pela loja ("Rosa", "Azul marinho"...). Nome desconhecido ganha uma
/// cor estável derivada do texto (a bolinha sempre aparece; o nome vai escrito ao lado).
Color colorFor(String name) {
  final n = name.toLowerCase();
  const known = {
    'preto': 0xFF1B1B1B, 'branco': 0xFFFAFAFA, 'off white': 0xFFF3EFE6, 'cinza': 0xFF9E9E9E, 'chumbo': 0xFF4A4F55,
    'vermelho': 0xFFD7263D, 'vinho': 0xFF6D1530, 'bordô': 0xFF6D1530, 'rosa': 0xFFF08FB0, 'pink': 0xFFE5267A,
    'nude': 0xFFE3BFA5, 'laranja': 0xFFF28C28, 'amarelo': 0xFFF5D547, 'mostarda': 0xFFD9A521, 'verde': 0xFF3A9D5D,
    'militar': 0xFF5B6B3C, 'azul': 0xFF2F6FDE, 'marinho': 0xFF1B2A5A, 'jeans': 0xFF4F6D9A, 'roxo': 0xFF7B3FA3,
    'lilás': 0xFFB69AE0, 'marrom': 0xFF7B4A2B, 'caramelo': 0xFFB5733A, 'bege': 0xFFD8C3A0, 'dourado': 0xFFD4AF37,
    'prata': 0xFFC0C0C0, 'prateado': 0xFFC0C0C0, 'vermelha': 0xFFD7263D, 'preta': 0xFF1B1B1B, 'branca': 0xFFFAFAFA,
  };
  for (final e in known.entries) {
    if (n.contains(e.key)) return Color(e.value);
  }
  var hash = 0;
  for (final u in n.codeUnits) {
    hash = (hash * 31 + u) & 0xffffff;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.45, 0.55).toColor();
}

/// Bolinha de cor selecionável.
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.name, required this.selected, required this.onTap, this.dimmed = false});

  final String name;
  final bool selected;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Opacity(
          opacity: dimmed ? 0.35 : 1,
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2.5 : 1),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: colorFor(name), border: Border.all(color: scheme.outlineVariant, width: 0.5)),
            ),
          ),
        ),
      ),
    );
  }
}
