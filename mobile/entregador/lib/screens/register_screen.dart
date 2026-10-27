import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../cpf.dart';

/// Cadastro do entregador. Cria a conta em `/api/auth/register-courier` (fica em análise até a plataforma aprovar)
/// e entra com ela.
class RegisterCourierScreen extends StatefulWidget {
  const RegisterCourierScreen({super.key, required this.session});

  final Session session;

  @override
  State<RegisterCourierScreen> createState() => _RegisterCourierScreenState();
}

class _RegisterCourierScreenState extends State<RegisterCourierScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _cpf = TextEditingController();
  final _password = TextEditingController();
  final _plate = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  String _vehicle = 'MOTO';
  double _radius = 10;
  GeoPoint? _base;
  bool _hidden = true;
  bool _busy = false;
  bool _locating = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _cpf, _password, _plate, _city, _state]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    try {
      final p = await currentPosition();
      if (mounted) {
        setState(() => _base = p);
        showInfo(context, 'Ponto da sua região marcado.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.session.registerCourier({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'cpf': cpfDigits(_cpf.text),
        'password': _password.text,
        'vehicle': _vehicle,
        if (_plate.text.trim().isNotEmpty) 'plate': _plate.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        if (_base != null) ...{'baseLat': _base!.lat, 'baseLng': _base!.lng},
        'radiusKm': _radius.round(),
      });
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
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
      appBar: AppBar(title: const Text('Cadastro de entregador')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Seu nome'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Informe seu nome' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: (v) => (v ?? '').contains('@') ? null : 'E-mail inválido',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp / telefone'),
              validator: (v) => (v ?? '').trim().length < 8 ? 'Informe o telefone com DDD' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cpf,
              keyboardType: TextInputType.number,
              inputFormatters: [CpfFormatter()],
              decoration: const InputDecoration(labelText: 'CPF', hintText: '000.000.000-00'),
              validator: (v) => cpfValid(v ?? '') ? null : 'CPF inválido',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _hidden,
              decoration: InputDecoration(
                labelText: 'Senha',
                helperText: 'Mínimo de 8 caracteres, com letras e números',
                suffixIcon: IconButton(
                  icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
              validator: (v) => passwordProblem(v ?? ''),
            ),
            const SizedBox(height: 20),
            Text('Como você entrega', style: t.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final e in vehicleLabels.entries)
                ChoiceChip(label: Text(e.value), selected: _vehicle == e.key, onSelected: (_) => setState(() => _vehicle = e.key)),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Placa (opcional)'),
            ),
            const SizedBox(height: 20),
            Text('Onde você atua', style: t.titleMedium),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
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
            OutlinedButton.icon(
              onPressed: _locating ? null : _useLocation,
              icon: _locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
              label: Text(_base == null ? 'Usar minha localização como base' : 'Base marcada · atualizar'),
            ),
            const SizedBox(height: 12),
            Text('Raio de atuação: ${_radius.round()} km', style: t.bodyLarge),
            Slider(value: _radius, min: 1, max: 50, divisions: 49, label: '${_radius.round()} km', onChanged: (v) => setState(() => _radius = v)),
            Text('Você só vê as corridas das lojas dentro desse raio a partir da sua posição (ou da base).', style: t.bodySmall),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enviar cadastro'),
            ),
            const SizedBox(height: 8),
            Text('Ao enviar você aceita os termos de uso e a política de privacidade. Seu cadastro será analisado.',
                textAlign: TextAlign.center, style: t.bodySmall),
          ]),
        ),
      ),
    );
  }
}
