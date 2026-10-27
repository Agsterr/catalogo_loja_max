import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'order_screen.dart';

/// Pedidos do cliente.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meus pedidos')),
        body: PagedList<OrderSummary>(
          load: (page) async =>
              PageResult.fromJson(await api.get('/api/orders?page=$page') as Map<String, dynamic>, OrderSummary.fromJson),
          empty: const EmptyState(icon: Icons.receipt_long_outlined, text: 'Você ainda não fez pedidos.'),
          itemBuilder: (context, o) => OrderTile(
            order: o,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(api: api, orderId: o.id))),
          ),
        ),
      );
}

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
