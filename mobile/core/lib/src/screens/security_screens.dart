import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

/// Verificação em duas etapas: ligar com um app autenticador (Google Authenticator, Authy...) ou desligar.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key, required this.session});

  final Session session;

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  String? _secret;
  String? _uri;
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.session.user?.twoFactorEnabled ?? false;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Duas etapas')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Icon(enabled ? Icons.verified_user_rounded : Icons.shield_outlined,
            size: 64, color: enabled ? Colors.green : Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(enabled ? 'Sua conta está protegida' : 'Proteja sua conta', textAlign: TextAlign.center, style: t.titleLarge),
        const SizedBox(height: 8),
        Text(
          enabled
              ? 'Ao entrar, além da senha, pedimos o código de 6 dígitos do seu app autenticador.'
              : 'Mesmo que alguém descubra sua senha, não entra sem o código que muda a cada 30 segundos no seu celular.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (!enabled && _secret == null)
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      final j = await widget.session.api.post('/api/me/2fa/setup') as Map<String, dynamic>;
                      setState(() {
                        _secret = j['secret'] as String;
                        _uri = j['otpauthUri'] as String;
                      });
                    }),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Ligar verificação em duas etapas'),
          ),
        if (!enabled && _secret != null) ...[
          Text('1. Abra o app autenticador e adicione esta conta:', style: t.titleSmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(_uri!), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Abrir no app autenticador'),
          ),
          const SizedBox(height: 8),
          Text('Ou digite a chave:', style: t.bodySmall),
          Row(children: [
            Expanded(child: SelectableText(_secret!, style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5))),
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _secret!));
                showInfo(context, 'Chave copiada.');
              },
            ),
          ]),
          const SizedBox(height: 16),
          Text('2. Digite o código que aparece no app:', style: t.titleSmall),
          const SizedBox(height: 8),
          TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Código')),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await widget.session.api.post('/api/me/2fa/enable', {'code': _code.text.trim()});
                      await widget.session.reloadUser();
                      if (context.mounted) showInfo(context, 'Verificação em duas etapas ligada.');
                      setState(() => _secret = null);
                    }),
            child: const Text('Confirmar e ligar'),
          ),
        ],
        if (enabled) ...[
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Sua senha')),
          const SizedBox(height: 12),
          TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Código do autenticador')),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await widget.session.api.post('/api/me/2fa/disable', {'password': _password.text, 'code': _code.text.trim()});
                      await widget.session.reloadUser();
                      if (context.mounted) showInfo(context, 'Verificação em duas etapas desligada.');
                    }),
            child: const Text('Desligar'),
          ),
        ],
      ]),
    );
  }
}

/// Lista de eventos de segurança: os acessos da própria conta ou a auditoria da loja (dono).
class SecurityEventsScreen extends StatelessWidget {
  const SecurityEventsScreen({super.key, required this.api, this.store = false});

  final ApiClient api;
  final bool store;

  @override
  Widget build(BuildContext context) {
    final path = store ? '/api/store/audit' : '/api/me/security-events';
    return Scaffold(
      appBar: AppBar(title: Text(store ? 'Auditoria da loja' : 'Acessos da conta')),
      body: PagedList<SecurityEvent>(
        load: (page) async => PageResult.fromJson(await api.get('$path?page=$page') as Map<String, dynamic>, SecurityEvent.fromJson),
        empty: const EmptyState(icon: Icons.history_rounded, text: 'Nada registrado ainda.'),
        separator: const Divider(height: 1),
        padding: EdgeInsets.zero,
        itemBuilder: (context, e) => ListTile(
          leading: Icon(e.alarming ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
              color: e.alarming ? Theme.of(context).colorScheme.error : null),
          title: Text(e.label),
          subtitle: Text([
            dateTime(e.createdAt),
            if (store) ?e.userName,
            ?e.detail,
            if (e.ip != null) 'IP ${e.ip}',
          ].join(' · ')),
        ),
      ),
    );
  }
}
