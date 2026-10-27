import 'package:flutter/material.dart';

import '../api_client.dart';
import '../session.dart';
import '../widgets.dart';

/// Entrar e recuperar a senha com o código enviado por e-mail. No app do cliente também cria a conta; no app do
/// lojista ([forStore]) abre uma loja nova — e é por ele que entram a equipe e o admin da plataforma.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session, this.popOnSuccess = true, this.forStore = false});

  final Session session;

  /// Aberta por cima da vitrine (ex.: ao fechar o pedido): volta para onde estava.
  final bool popOnSuccess;

  /// App do lojista: sem cadastro de cliente, com "Abrir minha loja".
  final bool forStore;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { login, register }

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  _Mode _mode = _Mode.login;

  /// A conta tem verificação em duas etapas: pede o código do app autenticador.
  bool _needsCode = false;
  bool _busy = false;
  bool _hidden = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email.text.isEmpty) _email.text = widget.session.lastEmail ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final session = widget.session;
    try {
      if (_mode == _Mode.login) {
        await session.login(_email.text, _password.text, code: _needsCode ? _code.text : null);
      } else {
        await session.register(name: _name.text, email: _email.text, phone: _phone.text, password: _password.text);
      }
      if (mounted && widget.popOnSuccess && Navigator.canPop(context)) Navigator.pop(context, true);
    } on AccountBlockedException {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context); // a tela de bloqueio aparece na raiz
    } on ApiException catch (e) {
      if (e.code == 'TOTP_REQUIRED' && mounted) {
        setState(() => _needsCode = true);
        showInfo(context, e.message);
      } else if (mounted) {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final register = _mode == _Mode.register;
    return Scaffold(
      appBar: Navigator.canPop(context) ? AppBar(title: Text(register ? 'Criar conta' : 'Entrar')) : null,
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const SizedBox(height: 24),
            Icon(widget.forStore ? Icons.storefront_rounded : Icons.shopping_bag_rounded,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(widget.forStore ? 'Loja Max Lojista' : 'Loja Max',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            if (widget.forStore)
              Text('Pedidos, estoque, fotos e promoções da sua loja', textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            if (register) ...[
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Seu nome'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v ?? '').trim().length < 2 ? 'Informe seu nome' : null,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (v) => (v ?? '').contains('@') ? null : 'E-mail inválido',
            ),
            const SizedBox(height: 12),
            if (register) ...[
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'WhatsApp (opcional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _password,
              obscureText: _hidden,
              decoration: InputDecoration(
                labelText: 'Senha',
                helperText: register ? 'Mínimo de 8 caracteres, com letras e números' : null,
                suffixIcon: IconButton(
                  icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
              validator: (v) {
                final s = v ?? '';
                if (!register) return s.isEmpty ? 'Informe a senha' : null;
                return passwordProblem(s);
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_needsCode && !register) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Código do app autenticador',
                  prefixIcon: Icon(Icons.verified_user_rounded),
                ),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(register ? 'Criar conta' : 'Entrar'),
            ),
            const SizedBox(height: 8),
            if (!widget.forStore)
              TextButton(
                onPressed: () => setState(() => _mode = register ? _Mode.login : _Mode.register),
                child: Text(register ? 'Já tenho conta' : 'Não tem conta? Criar agora'),
              ),
            if (!register)
              TextButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(email: _email.text.trim()))),
                child: const Text('Esqueci minha senha'),
              ),
            if (widget.forStore) ...[
            const Divider(height: 32),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RegisterStoreScreen(session: widget.session)));
                if (ok == true && context.mounted && widget.popOnSuccess && Navigator.canPop(context)) {
                  Navigator.pop(context, true);
                }
              },
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Abrir minha loja'),
            ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Lojista abre a loja: nome, endereço (slug) e a conta do dono.
class RegisterStoreScreen extends StatefulWidget {
  const RegisterStoreScreen({super.key, required this.session});

  final Session session;

  @override
  State<RegisterStoreScreen> createState() => _RegisterStoreScreenState();
}

class _RegisterStoreScreenState extends State<RegisterStoreScreen> {
  final _form = GlobalKey<FormState>();
  final _store = TextEditingController();
  final _slug = TextEditingController();
  final _owner = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _slugTouched = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_store, _slug, _owner, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.session.registerStore(
            storeName: _store.text,
            slug: _slug.text,
            ownerName: _owner.text,
            email: _email.text,
            password: _password.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abrir minha loja')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Cadastre a loja e já comece a vender: vitrine, pedidos, estoque, fotos e avisos no celular.',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
          TextFormField(
            controller: _store,
            decoration: const InputDecoration(labelText: 'Nome da loja'),
            textCapitalization: TextCapitalization.words,
            onChanged: (v) {
              if (!_slugTouched) _slug.text = slugify(v);
            },
            validator: (v) => (v ?? '').trim().length < 2 ? 'Informe o nome da loja' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _slug,
            decoration: const InputDecoration(labelText: 'Endereço da loja', helperText: 'Os clientes acham a loja por ele'),
            onChanged: (_) => _slugTouched = true,
            validator: (v) => RegExp(r'^[a-z0-9-]{3,60}$').hasMatch(v ?? '')
                ? null
                : 'Use de 3 a 60 letras minúsculas, números e hífen',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _owner,
            decoration: const InputDecoration(labelText: 'Seu nome'),
            textCapitalization: TextCapitalization.words,
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
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha', helperText: 'Mínimo de 8 caracteres, com letras e números'),
            validator: (v) => passwordProblem(v ?? ''),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Criar minha loja'),
          ),
        ]),
      ),
    );
  }
}

/// "Moda da Ana" → "moda-da-ana" (sem acento, só letras, números e hífen).
String slugify(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final lower = s.toLowerCase().split('').map((c) {
    final i = from.indexOf(c);
    return i >= 0 ? to[i] : c;
  }).join();
  return lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Mesma regra da API: 8+ caracteres, com letra e número.
String? passwordProblem(String s) {
  if (s.length < 8) return 'Use pelo menos 8 caracteres';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Use letras e números';
  return null;
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});

  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(ApiClient api) action) async {
    setState(() => _busy = true);
    try {
      await action(ApiClient());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar senha')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(_sent
            ? 'Se existir uma conta com esse e-mail, enviamos um código de 8 letras/números. Ele vale por 1 hora.'
            : 'Informe seu e-mail. Vamos mandar um código para você criar uma senha nova.'),
        const SizedBox(height: 16),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
        if (_sent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código do e-mail'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Nova senha')),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _sent
                  ? _run((api) async {
                      final problem = passwordProblem(_password.text);
                      if (problem != null) return showInfo(context, problem);
                      await api.post('/api/auth/reset-password',
                          {'email': _email.text.trim(), 'code': _code.text.trim(), 'password': _password.text});
                      if (!context.mounted) return;
                      showInfo(context, 'Senha trocada. Entre com a senha nova.');
                      Navigator.pop(context);
                    })
                  : _run((api) async {
                      await api.post('/api/auth/forgot-password', {'email': _email.text.trim()});
                      setState(() => _sent = true);
                    }),
          child: Text(_sent ? 'Trocar senha' : 'Enviar código'),
        ),
      ]),
    );
  }
}
