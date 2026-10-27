import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';


/// Pedidos do cliente na loja aberta.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, required this.api, required this.slug});

  final ApiClient api;
  final String slug;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Meus pedidos')),
        body: PagedList<OrderSummary>(
          load: (page) async =>
              PageResult.fromJson(await api.get('/api/stores/$slug/orders?page=$page') as Map<String, dynamic>, OrderSummary.fromJson),
          empty: const EmptyState(icon: Icons.receipt_long_outlined, text: 'Você ainda não fez pedidos.'),
          itemBuilder: (context, o) => OrderTile(
            order: o,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(api: api, orderId: o.id, slug: slug))),
          ),
        ),
      );
}
