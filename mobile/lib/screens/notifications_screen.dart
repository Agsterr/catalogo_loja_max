import 'package:flutter/material.dart';

import '../background.dart';
import '../format.dart';
import '../models.dart';
import '../notifications.dart';
import '../session.dart';
import '../widgets/common.dart';

/// Sino: avisos da loja (equipe) ou do cliente. Tocar abre o pedido ou o produto.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.session, required this.onOpen, this.onUnread});

  final Session session;

  /// Abre o que o aviso aponta ("order:12@loja" / "product:5@loja").
  final void Function(String payload) onOpen;

  /// Contagem de não lidos (para o selo da aba).
  final ValueChanged<int>? onUnread;

  @override
  State<NotificationsScreen> createState() => NotificationsScreenState();
}

class NotificationsScreenState extends State<NotificationsScreen> {
  Inbox? _inbox;
  Object? _error;
  int _page = 0;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final inbox = Inbox.fromJson(await widget.session.api.get('/api/notifications?page=0') as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _inbox = inbox;
        _page = 0;
        _error = null;
      });
      widget.onUnread?.call(inbox.unread);
      // o que já apareceu aqui não vira notificação de novo no segundo plano
      if (inbox.items.isNotEmpty) await markNotified(inbox.items.first.id);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Próxima página do sino (rolagem infinita).
  Future<void> _more() async {
    final inbox = _inbox;
    if (inbox == null || !inbox.hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = Inbox.fromJson(await widget.session.api.get('/api/notifications?page=${_page + 1}') as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _inbox = Inbox(next.unread, [...inbox.items, ...next.items], hasMore: next.hasMore);
        _page++;
      });
    } catch (_) {
      // tenta de novo ao rolar
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _readAll() async {
    try {
      await widget.session.api.post('/api/notifications/read');
      await refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      widget.session.api.post('/api/notifications/${n.id}/read').then((_) => refresh()).catchError((Object _) {});
    }
    final payload = payloadFor(orderId: n.orderId, productId: n.productId, slug: n.storeSlug);
    if (payload.isNotEmpty) widget.onOpen(payload);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = _inbox;
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos'), actions: [
        if ((inbox?.unread ?? 0) > 0)
          TextButton(onPressed: _readAll, child: const Text('Marcar lidos')),
      ]),
      body: inbox == null
          ? (_error != null
              ? ErrorRetry(message: 'Não foi possível carregar os avisos.', onRetry: refresh)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: refresh,
              child: inbox.items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      EmptyState(icon: Icons.notifications_none_rounded, text: 'Nenhum aviso por enquanto.'),
                    ])
                  : NotificationListener<ScrollNotification>(
                      onNotification: (sn) {
                        if (sn.metrics.pixels > sn.metrics.maxScrollExtent - 300) _more();
                        return false;
                      },
                      child: ListView.separated(
                      itemCount: inbox.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = inbox.items[i];
                        return ListTile(
                          leading: CircleAvatar(child: Icon(_icon(n.type))),
                          title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.w700)),
                          subtitle: Text('${n.message}\n${[
                            ago(n.createdAt),
                            if (!(widget.session.user?.isTeam ?? false)) ?n.storeName,
                          ].join(' · ')}'),
                          isThreeLine: true,
                          onTap: () => _open(n),
                        );
                      },
                    ),
                    ),
            ),
    );
  }

  static IconData _icon(String type) => switch (type) {
        'NEW_ORDER' => Icons.shopping_bag_rounded,
        'ORDER_CANCELED' => Icons.remove_shopping_cart_rounded,
        'LOW_STOCK' || 'OUT_OF_STOCK' => Icons.inventory_2_rounded,
        'ORDER_PAID' => Icons.payments_rounded,
        'BACK_IN_STOCK' => Icons.celebration_rounded,
        _ => Icons.local_shipping_rounded,
      };
}
