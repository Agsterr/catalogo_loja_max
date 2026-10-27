import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';
import '../courier_api.dart';

/// Conta do entregador: resumo, região/veículo e as telas comuns (senha, segurança, sair, excluir).
class AccountTab extends StatelessWidget {
  const AccountTab({super.key, required this.api, required this.profile, required this.onProfile});

  final CourierApi api;
  final CourierProfile profile;
  final ValueChanged<CourierProfile> onProfile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final session = AppScope.of(context).session;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 26, backgroundColor: scheme.primaryContainer, child: const Icon(Icons.two_wheeler_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profile.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${vehicleLabels[profile.vehicle] ?? profile.vehicle}${profile.plate == null ? '' : ' · ${profile.plate}'}', style: t.bodyMedium),
                  ]),
                ),
              ]),
              const Divider(height: 24),
              Text('Atua em ${profile.city} - ${profile.state}, raio de ${profile.radiusKm} km', style: t.bodyMedium),
              const SizedBox(height: 4),
              Text('${profile.deliveredCount} entregas · ${profile.canceledCount} desistências', style: t.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.edit_location_alt_rounded),
          title: const Text('Região e veículo'),
          subtitle: const Text('Cidade, raio de atuação, ponto base, veículo e telefone'),
          onTap: () async {
            final updated = await Navigator.push<CourierProfile>(
                context, MaterialPageRoute(builder: (_) => EditProfileScreen(api: api, profile: profile)));
            if (updated != null) onProfile(updated);
          },
        ),
        ListTile(
          leading: const Icon(Icons.person_rounded),
          title: const Text('Minha conta'),
          subtitle: const Text('Senha, verificação em duas etapas, sair, excluir conta'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountScreen(session: session))),
        ),
      ]),
    );
  }
}

/// Edita região de atuação, veículo e telefone (`PUT /api/courier/me`).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.api, required this.profile});

  final CourierApi api;
  final CourierProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _plate = TextEditingController(text: widget.profile.plate ?? '');
  late final _city = TextEditingController(text: widget.profile.city);
  late final _state = TextEditingController(text: widget.profile.state);
  late String _vehicle = widget.profile.vehicle;
  late double _radius = widget.profile.radiusKm.toDouble();
  double? _lat;
  double? _lng;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lat = widget.profile.baseLat;
    _lng = widget.profile.baseLng;
  }

  @override
  void dispose() {
    for (final c in [_phone, _plate, _city, _state]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useLocation() async {
    try {
      final p = await currentPosition();
      if (mounted) {
        setState(() {
          _lat = p.lat;
          _lng = p.lng;
        });
        showInfo(context, 'Ponto base atualizado. Toque em Salvar.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final p = await widget.api.update({
        'phone': _phone.text.trim(),
        'vehicle': _vehicle,
        'plate': _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'baseLat': _lat,
        'baseLng': _lng,
        'radiusKm': _radius.round(),
      });
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Região e veículo')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefone'),
            validator: (v) => (v ?? '').trim().length < 8 ? 'Informe o telefone com DDD' : null,
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: [
            for (final e in vehicleLabels.entries)
              ChoiceChip(label: Text(e.value), selected: _vehicle == e.key, onSelected: (_) => setState(() => _vehicle = e.key)),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: _plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Placa (opcional)')),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'Cidade'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Informe a cidade' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _state,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'UF', counterText: ''),
                validator: (v) => RegExp(r'^[A-Za-z]{2}$').hasMatch((v ?? '').trim()) ? null : 'UF',
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _useLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: Text(_lat == null ? 'Marcar minha base' : 'Base marcada · atualizar'),
              ),
            ),
            if (_lat != null) IconButton(tooltip: 'Remover base', onPressed: () => setState(() => _lat = _lng = null), icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: 12),
          Text('Raio de atuação: ${_radius.round()} km', style: t.bodyLarge),
          Slider(value: _radius, min: 1, max: 50, divisions: 49, label: '${_radius.round()} km', onChanged: (v) => setState(() => _radius = v)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
          ),
        ]),
      ),
    );
  }
}
