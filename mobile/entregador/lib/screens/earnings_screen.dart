import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../courier_api.dart';

/// Ganhos de hoje, da semana e do mês, e o histórico de corridas.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.api, required this.visible});

  final CourierApi api;

  /// Aba à vista: recarrega ao abrir.
  final bool visible;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  CourierEarnings? _earnings;
  Object? _error;
  var _key = GlobalKey<PagedListState<CourierJob>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EarningsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _load();
      setState(() => _key = GlobalKey());
    }
  }

  Future<void> _load() async {
    try {
      final e = await widget.api.earnings();
      if (mounted) {
        setState(() {
          _earnings = e;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = _earnings;
    return SafeArea(
      child: Column(children: [
        if (e != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Expanded(child: _Tile('Hoje', e.today)),
              const SizedBox(width: 8),
              Expanded(child: _Tile('Semana', e.week)),
              const SizedBox(width: 8),
              Expanded(child: _Tile('Mês', e.month)),
            ]),
          )
        else if (_error != null)
          ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: _load),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Align(alignment: Alignment.centerLeft, child: Text('Histórico', style: t.titleMedium)),
        ),
        Expanded(
          child: PagedList<CourierJob>(
            key: _key,
            load: widget.api.history,
            empty: const EmptyState(icon: Icons.history_rounded, text: 'Suas entregas concluídas aparecem aqui.'),
            itemBuilder: (context, j) => Card(
              child: ListTile(
                leading: Icon(j.status == 'DELIVERED' ? Icons.check_circle_rounded : Icons.cancel_outlined,
                    color: j.status == 'DELIVERED' ? Colors.green : Theme.of(context).colorScheme.outline),
                title: Text('${j.storeName} · #${j.orderCode}'),
                subtitle: Text([j.statusLabel, kmLabel(j.tripKm), if (j.deliveredAt != null) dateTime(j.deliveredAt!)].join(' · ')),
                trailing: Text(money(j.fee), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.period);

  final String label;
  final EarningsPeriod period;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, child: Text(money(period.total), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        Text(period.count == 1 ? '1 entrega' : '${period.count} entregas', style: t.bodySmall),
      ]),
    );
  }
}
