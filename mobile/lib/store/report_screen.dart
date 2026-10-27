import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Resumo de vendas do período (padrão: mês atual). Cancelados não contam.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTimeRange _range;
  Map<String, dynamic>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month), end: DateTime(now.year, now.month, now.day));
    _load();
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await widget.api.get('/api/store/reports/summary?from=${_iso(_range.start)}&to=${_iso(_range.end)}');
      if (mounted) setState(() => _data = data as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Resumo de vendas'), actions: [
        IconButton(
          icon: const Icon(Icons.date_range_rounded),
          onPressed: () async {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime.now(),
              initialDateRange: _range,
            );
            if (r != null) {
              setState(() => _range = r);
              _load();
            }
          },
        ),
      ]),
      body: d == null
          ? (_error != null ? ErrorRetry(message: '$_error', onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('${date(_range.start)} a ${date(_range.end)}', style: t.bodySmall),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _Stat('Faturamento', money(d['revenue'] as num)),
                  _Stat('Recebido', money(d['paidRevenue'] as num)),
                  _Stat('Pedidos', '${d['orders']}'),
                  _Stat('Ticket médio', money(d['averageTicket'] as num)),
                  _Stat('Peças vendidas', '${d['itemsSold']}'),
                  _Stat('Aguardando agora', '${d['pendingNow']}'),
                ]),
                const SizedBox(height: 20),
                Text('Mais vendidos', style: t.titleMedium),
                for (final p in (d['topProducts'] as List).cast<Map<String, dynamic>>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p['name'] as String),
                    trailing: Text('${p['quantity']} · ${money(p['revenue'] as num)}'),
                  ),
                const SizedBox(height: 12),
                Text('Estoque baixo', style: t.titleMedium),
                if ((d['lowStock'] as List).isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Tudo certo com o estoque.')),
                for (final s in (d['lowStock'] as List).cast<Map<String, dynamic>>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.inventory_2_rounded,
                        color: s['stock'] == 0 ? Theme.of(context).colorScheme.error : null),
                    title: Text(s['productName'] as String),
                    subtitle: Text(s['variant'] as String),
                    trailing: Text(s['stock'] == 0 ? 'Esgotado' : '${s['stock']} un.'),
                  ),
                const SizedBox(height: 12),
                Text('Por status', style: t.titleMedium),
                for (final e in (d['byStatus'] as Map<String, dynamic>).entries)
                  ListTile(contentPadding: EdgeInsets.zero, title: Text(OrderStatus.of(e.key).label), trailing: Text('${e.value}')),
              ]),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 160,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              FittedBox(child: Text(value, style: Theme.of(context).textTheme.titleLarge)),
            ]),
          ),
        ),
      );
}
