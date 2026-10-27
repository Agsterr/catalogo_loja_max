import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';

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

/// Foto do produto (R2) com fundo neutro enquanto carrega ou quando não tem.
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
          : Image.network(url!, fit: fit, errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) => progress == null ? child : placeholder),
    );
  }
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
    final (bg, fg) = switch (status) {
      OrderStatus.pending => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
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
