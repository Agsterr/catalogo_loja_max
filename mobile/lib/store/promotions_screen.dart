import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Promoções por período: % de desconto na loja toda, num departamento, numa categoria ou num produto.
/// Com "Avisar os clientes" ligado, o push sai quando a promoção começa.
class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  List<Promotion>? _list;
  List<Category> _categories = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.get('/api/store/promotions') as List;
      final cats = await widget.api.get('/api/store/categories') as List;
      if (!mounted) return;
      setState(() {
        _list = list.map((p) => Promotion.fromJson(p as Map<String, dynamic>)).toList();
        _categories = cats.map((c) => Category.fromJson(c as Map<String, dynamic>)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Promotion? p]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PromotionForm(api: widget.api, promotion: p, categories: _categories),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Promoções')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Promoção'),
      ),
      body: list == null
          ? (_error != null ? ErrorRetry(message: '$_error', onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : list.isEmpty
              ? const EmptyState(icon: Icons.local_offer_outlined, text: 'Nenhuma promoção ainda.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return Card(
                      child: ListTile(
                        onTap: () => _edit(p),
                        leading: CircleAvatar(child: Text('${p.discountPercent}%', style: const TextStyle(fontSize: 12))),
                        title: Text(p.title),
                        subtitle: Text('${p.scope} · ${dateTime(p.startsAt)} até ${dateTime(p.endsAt)}'),
                        trailing: p.running
                            ? const Chip(label: Text('Valendo'))
                            : Text(!p.active ? 'Pausada' : p.endsAt.isBefore(DateTime.now()) ? 'Encerrada' : 'Agendada'),
                      ),
                    );
                  },
                ),
    );
  }
}

class _PromotionForm extends StatefulWidget {
  const _PromotionForm({required this.api, this.promotion, required this.categories});

  final ApiClient api;
  final Promotion? promotion;
  final List<Category> categories;

  @override
  State<_PromotionForm> createState() => _PromotionFormState();
}

class _PromotionFormState extends State<_PromotionForm> {
  late final _title = TextEditingController(text: widget.promotion?.title ?? '');
  late final _description = TextEditingController(text: widget.promotion?.description ?? '');
  late double _percent = (widget.promotion?.discountPercent ?? 20).toDouble();
  late Department? _department = widget.promotion?.department;
  late int? _categoryId = widget.promotion?.categoryId;
  late DateTime _start = widget.promotion?.startsAt ?? DateTime.now();
  late DateTime _end = widget.promotion?.endsAt ?? DateTime.now().add(const Duration(days: 7));
  late bool _active = widget.promotion?.active ?? true;
  late bool _notify = widget.promotion?.notifyCustomers ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2100));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    return DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 19);

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return showInfo(context, 'Dê um título para a promoção.');
    setState(() => _busy = true);
    final body = {
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'discountPercent': _percent.round(),
      'department': _categoryId == null ? _department?.api : null,
      'categoryId': _categoryId,
      'productId': widget.promotion?.productId,
      'startsAt': _iso(_start),
      'endsAt': _iso(_end),
      'active': _active,
      'notifyCustomers': _notify,
    };
    try {
      if (widget.promotion == null) {
        await widget.api.post('/api/store/promotions', body);
      } else {
        await widget.api.put('/api/store/promotions/${widget.promotion!.id}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories.where((c) => _department == null || c.department == _department).toList();
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Título (aparece no aviso)')),
          const SizedBox(height: 12),
          TextField(controller: _description, decoration: const InputDecoration(labelText: 'Detalhe (opcional)')),
          const SizedBox(height: 12),
          Text('Desconto: ${_percent.round()}%'),
          Slider(value: _percent, min: 5, max: 90, divisions: 17, label: '${_percent.round()}%', onChanged: (v) => setState(() => _percent = v)),
          DropdownButtonFormField<Department?>(
            initialValue: _department,
            decoration: const InputDecoration(labelText: 'Vale para'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Loja inteira')),
              for (final d in Department.values) DropdownMenuItem(value: d, child: Text(d.label)),
            ],
            onChanged: (v) => setState(() {
              _department = v;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            key: ValueKey('promo-cat-${_department?.api}'),
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Só a categoria (opcional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todas')),
              for (final c in cats) DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.department.label})')),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final d = await _pick(_start);
                  if (d != null) setState(() => _start = d);
                },
                child: Text('Início\n${dateTime(_start)}', textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final d = await _pick(_end);
                  if (d != null) setState(() => _end = d);
                },
                child: Text('Fim\n${dateTime(_end)}', textAlign: TextAlign.center),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisar os clientes no celular'),
            subtitle: const Text('O aviso sai quando a promoção começar'),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ativa'), value: _active, onChanged: (v) => setState(() => _active = v)),
          Row(children: [
            if (widget.promotion != null)
              TextButton(
                onPressed: () async {
                  if (!await confirm(context, 'Apagar promoção?', 'Os preços voltam ao normal.', ok: 'Apagar')) return;
                  try {
                    await widget.api.delete('/api/store/promotions/${widget.promotion!.id}');
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                child: const Text('Apagar'),
              ),
            const Spacer(),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Salvar')),
          ]),
        ]),
      ),
    );
  }
}
