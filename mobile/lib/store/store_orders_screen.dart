import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../screens/order_screen.dart';
import '../screens/orders_screen.dart';
import '../widgets/common.dart';

/// Pedidos da loja: em aberto (padrão) ou por status, com busca por código/cliente.
class StoreOrdersScreen extends StatefulWidget {
  const StoreOrdersScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<StoreOrdersScreen> createState() => StoreOrdersScreenState();
}

class StoreOrdersScreenState extends State<StoreOrdersScreen> {
  OrderStatus? _status;
  bool _all = false;
  String _q = '';
  var _listKey = GlobalKey<PagedListState<OrderSummary>>();

  void refresh() => _listKey.currentState?.refresh();

  void _filter(void Function() change) {
    setState(() {
      change();
      _listKey = GlobalKey<PagedListState<OrderSummary>>();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Código ou cliente', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => _filter(() => _q = v.trim()),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
                ChoiceChip(
                  label: const Text('Em aberto'),
                  selected: _status == null && !_all,
                  onSelected: (_) => _filter(() {
                    _status = null;
                    _all = false;
                  }),
                ),
                const SizedBox(width: 8),
                for (final s in OrderStatus.values) ...[
                  ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => _filter(() => _status = s)),
                  const SizedBox(width: 8),
                ],
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _all && _status == null,
                  onSelected: (_) => _filter(() {
                    _status = null;
                    _all = true;
                  }),
                ),
              ]),
            ),
          ]),
        ),
      ),
      body: PagedList<OrderSummary>(
        key: _listKey,
        load: (page) async {
          final query = {
            'page': '$page',
            if (_status != null) 'status': _status!.api,
            'open': '${_status == null && !_all}',
            if (_q.isNotEmpty) 'q': _q,
          };
          return PageResult.fromJson(
              await widget.api.get('/api/store/orders?${Uri(queryParameters: query).query}') as Map<String, dynamic>,
              OrderSummary.fromJson);
        },
        empty: const EmptyState(icon: Icons.inbox_outlined, text: 'Nenhum pedido aqui.'),
        itemBuilder: (context, o) => OrderTile(
          order: o,
          showCustomer: true,
          onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => OrderScreen(api: widget.api, orderId: o.id, team: true)))
              .then((_) => refresh()),
        ),
      ),
    );
  }
}
