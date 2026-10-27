import 'dart:io';

import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


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

  /// Baixa a planilha (CSV, abre no Excel e no Google Planilhas) e abre o menu de compartilhar do celular.
  Future<void> _export(String kind) async {
    try {
      final path = kind == 'orders'
          ? '/api/store/reports/orders.csv?from=${_iso(_range.start)}&to=${_iso(_range.end)}'
          : '/api/store/reports/stock.csv';
      final bytes = await widget.api.getBytes(path);
      final dir = await getTemporaryDirectory();
      final name = kind == 'orders' ? 'vendas-${_iso(_range.start)}-a-${_iso(_range.end)}.csv' : 'estoque-${_iso(DateTime.now())}.csv';
      final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: name));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

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
        PopupMenuButton<String>(
          icon: const Icon(Icons.download_rounded),
          tooltip: 'Exportar planilha',
          onSelected: _export,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'orders', child: Text('Vendas do período (planilha)')),
            PopupMenuItem(value: 'stock', child: Text('Estoque atual (planilha)')),
          ],
        ),
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
                  _Stat('Clientes novos', '${d['newCustomers']}'),
                  _Stat('Descontos dados', money(d['discounts'] as num)),
                  _Stat('Aguardando agora', '${d['pendingNow']}'),
                ]),
                const SizedBox(height: 20),
                Text('Faturamento por dia', style: t.titleMedium),
                const SizedBox(height: 8),
                _DailyBars(days: (d['days'] as List).cast<Map<String, dynamic>>()),
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
        // duas colunas que ocupam a largura toda (32 = margens da lista, 12 = espaço entre os cartões)
        width: (MediaQuery.sizeOf(context).width - 32 - 12) / 2,
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

/// Barras do faturamento diário (uma série só: o título já diz o que é). Tocar numa barra mostra o dia e o valor.
class _DailyBars extends StatefulWidget {
  const _DailyBars({required this.days});

  final List<Map<String, dynamic>> days;

  @override
  State<_DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<_DailyBars> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final days = widget.days;
    if (days.isEmpty) {
      return const Padding(padding: EdgeInsets.all(8), child: Text('Sem vendas no período.'));
    }
    final values = [for (final d in days) (d['revenue'] as num).toDouble()];
    final max = values.reduce((a, b) => a > b ? a : b);
    final sel = _selected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            sel == null
                ? 'Maior dia: ${money(max)}'
                : '${date(DateTime.parse(days[sel]['date'] as String))} · ${money(values[sel])} · ${days[sel]['orders']} pedidos',
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque, // a área de toque é a coluna toda, não só a barra
                    onTap: () => setState(() => _selected = _selected == i ? null : i),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1), // 2px entre as barras
                        height: max == 0 ? 2 : (values[i] / max * 136).clamp(2, 136),
                        decoration: BoxDecoration(
                          color: sel == null || sel == i ? scheme.primary : scheme.primary.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 4),
          Row(children: [
            Text(date(DateTime.parse(days.first['date'] as String)), style: t.bodySmall),
            const Spacer(),
            Text(date(DateTime.parse(days.last['date'] as String)), style: t.bodySmall),
          ]),
        ]),
      ),
    );
  }
}
