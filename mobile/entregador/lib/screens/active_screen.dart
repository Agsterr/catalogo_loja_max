import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../courier_api.dart';

/// Corridas em andamento: passo a passo (ir à loja → código de coleta → ir ao cliente → código de entrega).
class ActiveScreen extends StatefulWidget {
  const ActiveScreen({super.key, required this.api, required this.onCount, required this.onChanged});

  final CourierApi api;

  /// Quantas corridas estão em andamento (badge da aba).
  final ValueChanged<int> onCount;

  /// Coleta, entrega ou desistência: o mural e os ganhos mudaram.
  final VoidCallback onChanged;

  @override
  State<ActiveScreen> createState() => ActiveScreenState();
}

class ActiveScreenState extends State<ActiveScreen> {
  List<CourierJob>? _jobs;
  Object? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final jobs = await widget.api.active();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _error = null;
      });
      widget.onCount(jobs.length);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    return SafeArea(
      child: jobs == null
          ? (_error != null
              ? ErrorRetry(message: _error is ApiException ? '$_error' : 'Não foi possível carregar.', onRetry: refresh)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: refresh,
              child: jobs.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      EmptyState(icon: Icons.two_wheeler_outlined, text: 'Nenhuma corrida em andamento. Aceite uma no mural.'),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: jobs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => JobCard(
                        key: ValueKey(jobs[i].id),
                        api: widget.api,
                        job: jobs[i],
                        onChanged: () {
                          widget.onChanged();
                          refresh();
                        },
                      ),
                    ),
            ),
    );
  }
}

/// Uma corrida aceita: mostra só o passo da vez.
class JobCard extends StatefulWidget {
  const JobCard({super.key, required this.api, required this.job, required this.onChanged});

  final CourierApi api;
  final CourierJob job;
  final VoidCallback onChanged;

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      _code.clear();
      if (mounted && done != null) showInfo(context, done);
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _giveUp() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desistir da corrida?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Ela volta para o mural e a loja é avisada. Desistir muitas vezes pode bloquear seu cadastro.'),
          const SizedBox(height: 12),
          TextField(controller: reason, maxLength: 200, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Desistir')),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok == true) await _run(() => widget.api.cancel(widget.job.id, text.isEmpty ? null : text), done: 'Você desistiu da corrida.');
  }

  Future<void> _map(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final toStore = !j.pickedUp;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Pedido #${j.orderCode}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text(money(j.fee), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _Step(number: 1, label: 'Loja', done: !toStore, current: toStore),
            const Expanded(child: Divider(indent: 8, endIndent: 8)),
            _Step(number: 2, label: 'Cliente', done: false, current: !toStore),
          ]),
          const SizedBox(height: 12),
          if (toStore) ...[
            Text('1. Vá até a loja', style: t.titleSmall),
            const SizedBox(height: 4),
            Text(j.storeName, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (j.pickupAddress != null) Text(j.pickupAddress!, style: t.bodyMedium),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _map(j.pickupLat, j.pickupLng),
              icon: const Icon(Icons.map_rounded),
              label: const Text('Abrir no mapa'),
            ),
            const SizedBox(height: 12),
            _CodeField(controller: _code, label: 'Código de coleta (peça à loja)'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : () => _run(() => widget.api.pickUp(j.id, _code.text.trim()), done: 'Coleta confirmada. Boa entrega!'),
              child: _busy ? const _Spinner() : const Text('Confirmar coleta'),
            ),
            TextButton(onPressed: _busy ? null : _giveUp, child: const Text('Desistir da corrida')),
          ] else ...[
            Text('2. Entregue ao cliente', style: t.titleSmall),
            const SizedBox(height: 4),
            if (j.customerName != null) Text(j.customerName!, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (j.dropoffAddress != null) Text(j.dropoffAddress!, style: t.bodyMedium),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _map(j.dropoffLat, j.dropoffLng),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Abrir no mapa'),
                ),
              ),
              if (j.customerPhone != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: j.customerPhone)),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Ligar'),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            _CodeField(controller: _code, label: 'Código de entrega (peça ao cliente)'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : () => _run(() => widget.api.deliver(j.id, _code.text.trim()), done: 'Entrega concluída! Valor somado aos seus ganhos.'),
              child: _busy ? const _Spinner() : const Text('Confirmar entrega'),
            ),
            const SizedBox(height: 4),
            Text('Depois da coleta não dá para desistir pelo app. Se houver problema, fale com o suporte.', style: t.bodySmall),
          ],
        ]),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: 4,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
        decoration: InputDecoration(labelText: label, counterText: ''),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.label, required this.done, required this.current});

  final int number;
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = done || current;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: on ? scheme.primary : scheme.surfaceContainerHighest,
        child: done
            ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
            : Text('$number', style: TextStyle(fontSize: 12, color: on ? scheme.onPrimary : scheme.outline)),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w400)),
    ]);
  }
}
