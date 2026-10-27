import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Cadastro/edição de produto: dados, preço, tamanhos/cores (com estoque) e fotos (vão para o Cloudflare R2).
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.api, this.productId});

  final ApiClient api;
  final int? productId;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _VariantDraft {
  _VariantDraft({this.id, String size = '', String color = '', String sku = '', this.stock = 0, this.active = true})
      : size = TextEditingController(text: size),
        color = TextEditingController(text: color),
        sku = TextEditingController(text: sku),
        initialStock = TextEditingController(text: '0');

  final int? id;
  final TextEditingController size;
  final TextEditingController color;
  final TextEditingController sku;
  final TextEditingController initialStock;
  int stock;
  bool active;

  void dispose() {
    size.dispose();
    color.dispose();
    sku.dispose();
    initialStock.dispose();
  }
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _brand = TextEditingController();
  final _price = TextEditingController();
  final _salePrice = TextEditingController();
  final _minStock = TextEditingController(text: '1');
  Department _department = Department.roupas;
  int? _categoryId;
  bool _active = true;
  bool _featured = false;
  final _variants = <_VariantDraft>[];
  List<Category> _categories = const [];
  List<Photo> _photos = const [];
  int? _id;
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _id = widget.productId;
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _brand, _price, _salePrice, _minStock]) {
      c.dispose();
    }
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await widget.api.get('/api/store/categories') as List;
      _categories = cats.map((c) => Category.fromJson(c as Map<String, dynamic>)).toList();
      if (_id != null) {
        _fill(Product.fromJson(await widget.api.get('/api/store/products/$_id') as Map<String, dynamic>));
      } else if (_variants.isEmpty) {
        _variants.add(_VariantDraft());
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _fill(Product p) {
    _name.text = p.name;
    _description.text = p.description ?? '';
    _brand.text = p.brand ?? '';
    _price.text = p.price.toStringAsFixed(2).replaceAll('.', ',');
    _salePrice.text = p.salePrice?.toStringAsFixed(2).replaceAll('.', ',') ?? '';
    _minStock.text = '${p.minStock}';
    _department = p.department;
    _categoryId = p.categoryId;
    _active = p.active;
    _featured = p.featured;
    _photos = p.photos;
    for (final v in _variants) {
      v.dispose();
    }
    _variants
      ..clear()
      ..addAll(p.variants.map((v) =>
          _VariantDraft(id: v.id, size: v.size, color: v.color, sku: v.sku ?? '', stock: v.stock, active: v.active)));
  }

  static double? _money(String s) => double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_variants.isEmpty) {
      showInfo(context, 'Cadastre pelo menos um tamanho (use "Único" para bijuterias).');
      return;
    }
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'department': _department.api,
      'categoryId': _categoryId,
      'brand': _brand.text.trim(),
      'price': _money(_price.text),
      'salePrice': _salePrice.text.trim().isEmpty ? null : _money(_salePrice.text),
      'minStock': int.tryParse(_minStock.text) ?? 1,
      'active': _active,
      'featured': _featured,
      'variants': [
        for (final v in _variants)
          {
            'id': v.id,
            'size': v.size.text.trim(),
            'color': v.color.text.trim(),
            'sku': v.sku.text.trim(),
            'initialStock': v.id == null ? int.tryParse(v.initialStock.text) ?? 0 : 0,
            'active': v.active,
          },
      ],
    };
    try {
      final json = _id == null
          ? await widget.api.post('/api/store/products', body)
          : await widget.api.put('/api/store/products/$_id', body);
      final p = Product.fromJson(json as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _id = p.id;
        _fill(p);
      });
      showInfo(context, 'Produto salvo.${_photos.isEmpty ? ' Agora adicione as fotos.' : ''}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 90);
    if (file == null || _id == null) return;
    setState(() => _busy = true);
    try {
      final json = await widget.api.upload('/api/store/products/$_id/photos', bytes: await file.readAsBytes(), filename: file.name);
      if (mounted) setState(() => _photos = [..._photos, Photo.fromJson(json as Map<String, dynamic>)]);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photoActions(Photo photo) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.star_rounded), title: const Text('Usar como capa'), onTap: () => Navigator.pop(context, 'cover')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Apagar foto'), onTap: () => Navigator.pop(context, 'delete')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'cover') {
        final ids = [photo.id, ..._photos.where((p) => p.id != photo.id).map((p) => p.id)];
        final list = await widget.api.put('/api/store/products/$_id/photos/order', {'ids': ids}) as List;
        setState(() => _photos = list.map((p) => Photo.fromJson(p as Map<String, dynamic>)).toList());
      } else {
        await widget.api.delete('/api/store/photos/${photo.id}');
        setState(() => _photos = _photos.where((p) => p.id != photo.id).toList());
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _stock(_VariantDraft v) async {
    final updated = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StockSheet(api: widget.api, variantId: v.id!, label: '${v.size.text} ${v.color.text}'.trim(), stock: v.stock),
    );
    if (updated != null && mounted) setState(() => v.stock = updated);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Excluir produto?', 'Se ele já foi vendido, só fica oculto da vitrine.', ok: 'Excluir')) return;
    try {
      final json = await widget.api.delete('/api/store/products/$_id') as Map<String, dynamic>;
      if (!mounted) return;
      showInfo(context, json['deleted'] == true ? 'Produto excluído.' : 'Produto já vendido: ficou oculto da vitrine.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: ErrorRetry(message: 'Não foi possível carregar.', onRetry: _load));
    }
    final t = Theme.of(context).textTheme;
    final categories = _categories.where((c) => c.department == _department && (c.active || c.id == _categoryId)).toList();
    final money = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));
    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'Novo produto' : 'Editar produto'),
        actions: [if (_id != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded))],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_id != null) ...[
            Text('Fotos', style: t.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in _photos)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _photoActions(p),
                      child: SizedBox(width: 96, child: ProductImage(url: p.thumbUrl)),
                    ),
                  ),
                _AddPhoto(icon: Icons.photo_camera_rounded, label: 'Câmera', onTap: _busy ? null : () => _addPhoto(ImageSource.camera)),
                const SizedBox(width: 8),
                _AddPhoto(icon: Icons.photo_library_rounded, label: 'Galeria', onTap: _busy ? null : () => _addPhoto(ImageSource.gallery)),
              ]),
            ),
            const SizedBox(height: 4),
            Text('A primeira foto é a capa. Toque numa foto para trocar a capa ou apagar.', style: t.bodySmall),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome'),
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Department>(
            initialValue: _department,
            decoration: const InputDecoration(labelText: 'Departamento'),
            items: [for (final d in Department.values) DropdownMenuItem(value: d, child: Text(d.label))],
            onChanged: (d) => setState(() {
              _department = d!;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            key: ValueKey('cat-${_department.api}'),
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sem categoria')),
              for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca (opcional)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [money],
                decoration: const InputDecoration(labelText: 'Preço', prefixText: 'R\$ '),
                validator: (v) => (_money(v ?? '') ?? 0) <= 0 ? 'Informe o preço' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _salePrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [money],
                decoration: const InputDecoration(labelText: 'Preço "por" (opcional)', prefixText: 'R\$ '),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return null;
                  final sale = _money(v!) ?? 0;
                  return sale <= 0 || sale >= (_money(_price.text) ?? 0) ? 'Menor que o preço' : null;
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            minLines: 2,
            maxLines: 6,
            maxLength: 4000,
            decoration: const InputDecoration(labelText: 'Descrição (tecido, medidas, cuidados…)'),
          ),
          TextFormField(
            controller: _minStock,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Avisar quando um tamanho chegar a', suffixText: 'peças'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('À venda na vitrine'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Destaque'),
            value: _featured,
            onChanged: (v) => setState(() => _featured = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Tamanhos e cores', style: t.titleMedium)),
            TextButton.icon(
              onPressed: () => setState(() => _variants.add(_VariantDraft())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar'),
            ),
          ]),
          for (final v in _variants) _variantCard(v),
          const SizedBox(height: 80),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_id == null ? 'Salvar e adicionar fotos' : 'Salvar'),
          ),
        ),
      ),
    );
  }

  Widget _variantCard(_VariantDraft v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: v.size,
                    decoration: const InputDecoration(labelText: 'Tamanho', hintText: 'P, M, 38, Único', isDense: true),
                    validator: (s) => (s ?? '').trim().isEmpty ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(controller: v.color, decoration: const InputDecoration(labelText: 'Cor', isDense: true)),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(controller: v.sku, decoration: const InputDecoration(labelText: 'Código (SKU)', isDense: true)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: v.id == null
                      ? TextFormField(
                          controller: v.initialStock,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Estoque inicial', isDense: true),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _stock(v),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text('${v.stock} em estoque'),
                        ),
                ),
              ]),
              Row(children: [
                Switch(value: v.active, onChanged: (a) => setState(() => v.active = a)),
                Text(v.active ? 'À venda' : 'Oculto'),
                const Spacer(),
                if (v.id == null)
                  IconButton(
                    onPressed: () => setState(() {
                      _variants.remove(v);
                      v.dispose();
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ]),
            ]),
          ),
        ),
      );
}

class _AddPhoto extends StatelessWidget {
  const _AddPhoto({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon), Text(label)]),
        ),
      );
}

/// Entrada de mercadoria, acerto de contagem ou perda — com o histórico do tamanho/cor.
class _StockSheet extends StatefulWidget {
  const _StockSheet({required this.api, required this.variantId, required this.label, required this.stock});

  final ApiClient api;
  final int variantId;
  final String label;
  final int stock;

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<_StockSheet> {
  String _type = 'IN';
  final _qty = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _history = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/store/variants/${widget.variantId}/stock').then((list) {
      if (mounted) setState(() => _history = (list as List).cast<Map<String, dynamic>>());
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qty.text);
    if (qty == null) return showInfo(context, 'Informe a quantidade.');
    setState(() => _busy = true);
    try {
      final json = await widget.api.post('/api/store/variants/${widget.variantId}/stock',
          {'type': _type, 'quantity': qty, 'note': _note.text.trim()}) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context, json['stock'] as int);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _labels = {'IN': 'Entrada', 'SALE': 'Venda', 'RETURN': 'Devolução', 'ADJUST': 'Contagem', 'LOSS': 'Perda'};

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.label} · ${widget.stock} em estoque', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'IN', label: Text('Entrada')),
              ButtonSegment(value: 'ADJUST', label: Text('Contagem')),
              ButtonSegment(value: 'LOSS', label: Text('Perda')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: _type == 'ADJUST' ? 'Quantidade contada' : 'Quantidade'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Lançar')),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Histórico', style: Theme.of(context).textTheme.titleSmall),
            for (final m in _history.take(15))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${_labels[m['type']] ?? m['type']}  ${(m['quantity'] as int) > 0 ? '+' : ''}${m['quantity']}'
                    ' → ${m['stockAfter']}'),
                subtitle: Text([dateTime(DateTime.parse(m['createdAt'] as String)), ?m['note'] as String?].join(' · ')),
              ),
          ],
        ]),
      ),
    );
  }
}
