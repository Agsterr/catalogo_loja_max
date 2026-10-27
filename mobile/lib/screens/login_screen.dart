import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

/// Entrar, criar conta (cliente) e recuperar a senha com o código enviado por e-mail.
/// A equipe da loja entra pela mesma tela; o app abre a gestão sozinho.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.popOnSuccess = true});

  /// Aberta por cima da vitrine (ex.: ao fechar o pedido): volta para onde estava.
  final bool popOnSuccess;

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
  _Mode _mode = _Mode.login;
  bool _busy = false;
  bool _hidden = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email.text.isEmpty) _email.text = AppScope.of(context).session.lastEmail ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final session = AppScope.of(context).session;
    try {
      if (_mode == _Mode.login) {
        await session.login(_email.text, _password.text);
      } else {
        await session.register(name: _name.text, email: _email.text, phone: _phone.text, password: _password.text);
      }
      if (mounted && widget.popOnSuccess && Navigator.canPop(context)) Navigator.pop(context, true);
    } on AccountBlockedException {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context); // a tela de bloqueio aparece na raiz
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
      appBar: AppBar(title: Text(register ? 'Criar conta' : 'Entrar')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Icon(Icons.shopping_bag_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text('Loja Max', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
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
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(register ? 'Criar conta' : 'Entrar'),
            ),
            const SizedBox(height: 8),
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
          ]),
        ),
      ),
    );
  }
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
