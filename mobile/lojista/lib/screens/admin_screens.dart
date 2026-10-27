import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loja_core/loja_core.dart';
import 'package:url_launcher/url_launcher.dart';


/// Categorias de cada departamento (ex.: Roupas › Vestidos).
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.get('/api/store/categories') as List;
      if (mounted) setState(() => _list = list.map((c) => Category.fromJson(c as Map<String, dynamic>)).toList());
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit([Category? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    var department = c?.department ?? Department.roupas;
    var active = c?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(c == null ? 'Nova categoria' : 'Editar categoria'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Department>(
              initialValue: department,
              decoration: const InputDecoration(labelText: 'Departamento'),
              items: [for (final d in Department.values) DropdownMenuItem(value: d, child: Text(d.label))],
              onChanged: (d) => setLocal(() => department = d!),
            ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome (ex.: Vestidos, Tênis, Colares)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aparece na vitrine'),
              value: active,
              onChanged: (v) => setLocal(() => active = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final body = {'department': department.api, 'name': name.text.trim(), 'position': c?.position ?? 0, 'active': active};
      try {
        if (c == null) {
          await widget.api.post('/api/store/categories', body);
        } else {
          await widget.api.put('/api/store/categories/${c.id}', body);
        }
        await _load();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add_rounded)),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              for (final d in Department.values) ...[
                ListTile(title: Text(d.label, style: Theme.of(context).textTheme.titleMedium)),
                for (final c in list.where((c) => c.department == d))
                  ListTile(
                    title: Text(c.name),
                    trailing: c.active ? null : const Text('Oculta'),
                    onTap: () => _edit(c),
                  ),
              ],
              const SizedBox(height: 80),
            ]),
    );
  }
}

/// Clientes que compraram na loja: busca, contato e bloqueio (dono) — bloqueado não faz pedidos nesta loja.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.api, required this.canBlock});

  final ApiClient api;
  final bool canBlock;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';
  var _key = GlobalKey<PagedListState<Map<String, dynamic>>>();

  Future<void> _toggleBlock(Map<String, dynamic> c) async {
    final blocked = c['blocked'] as bool;
    String? reason;
    if (!blocked) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Bloquear ${c['name']}?'),
          content: TextField(controller: controller, maxLength: 300, decoration: const InputDecoration(labelText: 'Motivo (o cliente vê)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bloquear')),
          ],
        ),
      );
      reason = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    }
    try {
      if (blocked) {
        await widget.api.post('/api/store/customers/${c['id']}/unblock');
      } else {
        await widget.api.post('/api/store/customers/${c['id']}/block', {'reason': reason});
      }
      _key.currentState?.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Nome, e-mail ou telefone', prefixIcon: Icon(Icons.search_rounded), isDense: true),
              onSubmitted: (v) => setState(() {
                _q = v.trim();
                _key = GlobalKey();
              }),
            ),
          ),
        ),
      ),
      body: PagedList<Map<String, dynamic>>(
        key: _key,
        load: (page) async => PageResult.fromJson(
            await widget.api.get('/api/store/customers?${Uri(queryParameters: {'page': '$page', 'q': _q}).query}')
                as Map<String, dynamic>,
            (j) => j),
        empty: const EmptyState(icon: Icons.people_outline_rounded, text: 'Nenhum cliente encontrado.'),
        separator: const Divider(height: 1),
        padding: EdgeInsets.zero,
        itemBuilder: (context, c) => ListTile(
          leading: Icon(c['blocked'] == true ? Icons.block_rounded : Icons.person_rounded),
          title: Text(c['name'] as String),
          subtitle: Text([
            c['email'],
            c['phone'],
            '${c['orders']} ${c['orders'] == 1 ? 'pedido' : 'pedidos'}',
            if (c['blocked'] == true) 'bloqueado aqui',
          ].whereType<String>().join(' · ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (c['phone'] != null)
              IconButton(
                icon: const Icon(Icons.chat_rounded),
                onPressed: () => launchUrl(whatsappUri(c['phone'] as String), mode: LaunchMode.externalApplication),
              ),
            if (widget.canBlock)
              IconButton(
                tooltip: c['blocked'] == true ? 'Desbloquear' : 'Bloquear',
                icon: Icon(c['blocked'] == true ? Icons.lock_open_rounded : Icons.block_rounded),
                onPressed: () => _toggleBlock(c),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Equipe (dono): funcionários entram pelo mesmo app e veem só a gestão.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<User>? _team;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.get('/api/store/users') as List;
      if (mounted) setState(() => _team = list.map((u) => User.fromJson(u as Map<String, dynamic>)).toList());
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo funcionário'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 12),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha inicial', helperText: '8+ caracteres, letras e números'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Criar')),
        ],
      ),
    );
    if (ok == true) {
      final problem = passwordProblem(password.text);
      if (problem != null) {
        if (mounted) showInfo(context, problem);
      } else {
        try {
          await widget.api.post('/api/store/users',
              {'name': name.text.trim(), 'email': email.text.trim(), 'password': password.text, 'role': 'STAFF'});
          await _load();
        } catch (e) {
          if (mounted) showError(context, e);
        }
      }
    }
    for (final c in [name, email, password]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = _team;
    return Scaffold(
      appBar: AppBar(title: const Text('Equipe')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.person_add_rounded)),
      body: team == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              for (final u in team)
                ListTile(
                  leading: Icon(u.isOwner ? Icons.workspace_premium_rounded : Icons.badge_rounded),
                  title: Text(u.name),
                  subtitle: Text('${u.email} · ${u.isOwner ? 'dono' : 'funcionário'}'),
                  trailing: u.isOwner
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.person_remove_rounded),
                          onPressed: () async {
                            if (!await confirm(context, 'Remover ${u.name}?', 'Ele sai do app na hora e para de receber os avisos.',
                                ok: 'Remover')) {
                              return;
                            }
                            try {
                              await widget.api.delete('/api/store/users/${u.id}');
                              await _load();
                            } catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          },
                        ),
                ),
            ]),
    );
  }
}

/// Dados da loja (dono): logo, capa, descrição, horário, WhatsApp, retirada, entrega e frete.
class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _whatsapp = TextEditingController();
  final _instagram = TextEditingController();
  final _address = TextEditingController();
  final _fee = TextEditingController();
  final _free = TextEditingController();
  final _city = TextEditingController();
  final _uf = TextEditingController();
  double? _lat;
  double? _lng;
  List<DeliveryZone> _zones = [];
  bool _pickup = true;
  bool _delivery = true;
  bool _loaded = false;
  bool _busy = false;
  String? _logoUrl;
  String? _coverUrl;
  String _slug = '';

  /// Segunda a domingo; "" = fechado.
  List<DayHours> _week = List.generate(7, (i) => i == 6 ? const DayHours('', '') : const DayHours('09:00', '18:00'));
  bool _hoursSet = false;

  static const _days = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/store/settings').then((j) {
      final s = StoreInfo.fromJson(j as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _slug = s.slug;
        _name.text = s.name;
        _description.text = s.description ?? '';
        _whatsapp.text = s.whatsapp ?? '';
        _instagram.text = s.instagram ?? '';
        _address.text = s.pickupAddress ?? '';
        _fee.text = s.deliveryFee.toStringAsFixed(2).replaceAll('.', ',');
        _city.text = s.city ?? '';
        _uf.text = s.state ?? '';
        _lat = s.latitude;
        _lng = s.longitude;
        _zones = [...s.deliveryZones];
        _free.text = s.freeDeliveryFrom?.toStringAsFixed(2).replaceAll('.', ',') ?? '';
        _pickup = s.pickupEnabled;
        _delivery = s.deliveryEnabled;
        _logoUrl = s.logoUrl;
        _coverUrl = s.coverUrl;
        if (s.openingHours != null && s.openingHours!.length == 7) {
          _week = s.openingHours!;
          _hoursSet = true;
        }
        _loaded = true;
      });
    }).catchError((Object e) {
      if (mounted) showError(context, e);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _whatsapp, _instagram, _address, _fee, _free, _city, _uf]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _money(String s) => double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

  Future<void> _useMyLocation() async {
    setState(() => _busy = true);
    try {
      final p = await currentPosition();
      if (mounted) {
        setState(() {
          _lat = p.lat;
          _lng = p.lng;
        });
        showInfo(context, 'Localização marcada. Toque em Salvar para guardar.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editZone([int? index]) async {
    final km = TextEditingController(text: index == null ? '' : _zones[index].upToKm.toString().replaceAll('.', ','));
    final fee = TextEditingController(text: index == null ? '' : _zones[index].fee.toStringAsFixed(2).replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faixa de entrega'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: km, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Até quantos km', suffixText: 'km')),
          const SizedBox(height: 12),
          TextField(controller: fee, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Taxa', prefixText: 'R\$ ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    final k = double.tryParse(km.text.trim().replaceAll(',', '.'));
    final f = _money(fee.text);
    km.dispose();
    fee.dispose();
    if (ok != true || !mounted) return;
    if (k == null || k <= 0 || k > 100 || f == null || f < 0) {
      showInfo(context, 'Informe a distância (até 100 km) e a taxa.');
      return;
    }
    setState(() {
      final z = DeliveryZone(k, f);
      if (index == null) {
        _zones = [..._zones, z];
      } else {
        _zones[index] = z;
      }
      _zones.sort((a, b) => a.upToKm.compareTo(b.upToKm));
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.put('/api/store/settings', {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'instagram': _instagram.text.trim(),
        'pickupAddress': _address.text.trim(),
        'pickupEnabled': _pickup,
        'deliveryEnabled': _delivery,
        'deliveryFee': _money(_fee.text) ?? 0,
        'freeDeliveryFrom': _free.text.trim().isEmpty ? null : _money(_free.text),
        'city': _city.text.trim(),
        'state': _uf.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
        'deliveryZones': _zones.map((z) => z.toJson()).toList(),
        'openingHours': _hoursSet ? _week.map((d) => d.toJson()).toList() : null,
      });
      if (mounted) showInfo(context, 'Dados da loja salvos.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// [kind]: 'logo' ou 'capa'.
  Future<void> _pickImage(String kind) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 90);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final json = StoreInfo.fromJson(
          await widget.api.upload('/api/store/settings/$kind', bytes: await file.readAsBytes(), filename: file.name) as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          _logoUrl = json.logoUrl;
          _coverUrl = json.coverUrl;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage(String kind) async {
    try {
      final json = StoreInfo.fromJson(await widget.api.delete('/api/store/settings/$kind') as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          _logoUrl = json.logoUrl;
          _coverUrl = json.coverUrl;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editDay(int i) async {
    final d = _week[i];
    TimeOfDay parse(String v, TimeOfDay fallback) {
      final p = v.split(':');
      return p.length == 2 ? TimeOfDay(hour: int.tryParse(p[0]) ?? fallback.hour, minute: int.tryParse(p[1]) ?? 0) : fallback;
    }

    String fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final open = await showTimePicker(
        context: context, helpText: '${_days[i]}: abre às', initialTime: parse(d.open, const TimeOfDay(hour: 9, minute: 0)));
    if (open == null || !mounted) return;
    final close = await showTimePicker(
        context: context, helpText: '${_days[i]}: fecha às', initialTime: parse(d.close, const TimeOfDay(hour: 18, minute: 0)));
    if (close == null) return;
    setState(() {
      _week = [..._week]..[i] = DayHours(fmt(open), fmt(close));
      _hoursSet = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Dados da loja')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('Sua vitrine', style: t.titleMedium),
              const SizedBox(height: 8),
              Stack(clipBehavior: Clip.none, children: [
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: _coverUrl != null
                      ? ProductImage(url: _coverUrl)
                      : Container(
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppTheme.brand, AppTheme.sale]), borderRadius: BorderRadius.circular(12)),
                        ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _pickImage('capa'),
                      icon: const Icon(Icons.image_rounded, size: 18),
                      label: const Text('Capa'),
                    ),
                    if (_coverUrl != null) IconButton(onPressed: () => _removeImage('capa'), icon: const Icon(Icons.close_rounded)),
                  ]),
                ),
                Positioned(left: 12, bottom: -28, child: StoreLogo(name: _name.text, url: _logoUrl, size: 64)),
              ]),
              const SizedBox(height: 36),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickImage('logo'),
                  icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                  label: Text(_logoUrl == null ? 'Escolher logo' : 'Trocar logo'),
                ),
                if (_logoUrl != null) TextButton(onPressed: () => _removeImage('logo'), child: const Text('Remover')),
              ]),
              const SizedBox(height: 4),
              Text('Endereço da loja: $_slug', style: t.bodySmall),
              const SizedBox(height: 16),
              TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nome da loja')),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Sobre a loja (aparece na vitrine)'),
              ),
              const SizedBox(height: 4),
              Text('Onde a loja fica', style: t.titleMedium),
              const SizedBox(height: 4),
              Text('Os clientes da sua região encontram a loja pela cidade e pela distância.', style: t.bodySmall),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    flex: 3,
                    child: TextField(controller: _city, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Cidade'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _uf,
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'UF', counterText: ''))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _useMyLocation,
                    icon: const Icon(Icons.my_location_rounded),
                    label: Text(_lat == null ? 'Marcar a loja no mapa (estou na loja)' : 'Localização marcada · atualizar'),
                  ),
                ),
                if (_lat != null) IconButton(tooltip: 'Remover localização', onPressed: () => setState(() => _lat = _lng = null), icon: const Icon(Icons.close_rounded)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _whatsapp, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp')),
              const SizedBox(height: 12),
              TextField(controller: _instagram, decoration: const InputDecoration(labelText: 'Instagram', prefixText: '@')),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: Text('Horário de funcionamento', style: t.titleMedium)),
                if (_hoursSet) TextButton(onPressed: () => setState(() => _hoursSet = false), child: const Text('Não informar')),
              ]),
              if (!_hoursSet)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _hoursSet = true),
                  icon: const Icon(Icons.schedule_rounded),
                  label: const Text('Informar horário (mostra "Aberta agora")'),
                )
              else
                for (var i = 0; i < 7; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_days[i]),
                    subtitle: Text(_week[i].closed ? 'Fechado' : '${_week[i].open} às ${_week[i].close}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!_week[i].closed)
                        TextButton(
                          onPressed: () => setState(() => _week = [..._week]..[i] = const DayHours('', '')),
                          child: const Text('Fechar'),
                        ),
                      IconButton(onPressed: () => _editDay(i), icon: const Icon(Icons.edit_rounded, size: 20)),
                    ]),
                  ),
              const Divider(height: 32),
              TextField(controller: _address, decoration: const InputDecoration(labelText: 'Endereço para retirada')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Retirada na loja'), value: _pickup, onChanged: (v) => setState(() => _pickup = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Entrega'), value: _delivery, onChanged: (v) => setState(() => _delivery = v)),
              if (_delivery) ...[
                if (_zones.isEmpty)
                  TextField(
                    controller: _fee,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Taxa de entrega (igual para todos)', prefixText: 'R\$ '),
                  ),
                const SizedBox(height: 12),
                Text('Entrega por distância', style: t.titleSmall),
                Text(
                    _lat == null
                        ? 'Marque a localização da loja (acima) para cobrar por distância.'
                        : 'Cada faixa vale até a distância informada; além da última, a loja não entrega. Sem faixas, vale a taxa acima.',
                    style: t.bodySmall),
                for (var i = 0; i < _zones.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Até ${kmLabel(_zones[i].upToKm)}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(money(_zones[i].fee), style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(onPressed: () => setState(() => _zones.removeAt(i)), icon: const Icon(Icons.delete_outline_rounded, size: 20)),
                    ]),
                    onTap: () => _editZone(i),
                  ),
                if (_zones.length < 6)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        onPressed: _lat == null ? null : _editZone,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Adicionar faixa')),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _free,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Entrega grátis a partir de (opcional)', prefixText: 'R\$ '),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Salvar')),
              const SizedBox(height: 24),
            ]),
    );
  }
}
