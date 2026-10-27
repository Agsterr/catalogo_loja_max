import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../format.dart';
import '../models.dart';
import '../push.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

/// Conta: dados, senha, avisos de promoção, sair (deste ou de todos os aparelhos) e excluir conta.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  StoreInfo? _store;
  bool _promos = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_store == null) {
      AppScope.of(context).session.api.get('/api/public/store').then((j) {
        if (mounted) setState(() => _store = StoreInfo.fromJson(j as Map<String, dynamic>));
      }).catchError((Object _) {});
    }
  }

  Future<void> _editProfile() async {
    final session = AppScope.of(context).session;
    final user = session.user!;
    final name = TextEditingController(text: user.name);
    final phone = TextEditingController(text: user.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seus dados'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await session.updateProfile(name.text.trim(), phone.text.trim().isEmpty ? null : phone.text.trim());
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final session = AppScope.of(context).session;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trocar senha'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Senha atual')),
          const SizedBox(height: 12),
          TextField(
            controller: next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nova senha', helperText: '8+ caracteres, letras e números'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Trocar')),
        ],
      ),
    );
    if (ok == true) {
      final problem = passwordProblem(next.text);
      if (problem != null) {
        if (mounted) showInfo(context, problem);
      } else {
        try {
          await session.changePassword(current.text, next.text);
          if (mounted) showInfo(context, 'Senha trocada. Os outros aparelhos foram desconectados.');
        } catch (e) {
          if (mounted) showError(context, e);
        }
      }
    }
    current.dispose();
    next.dispose();
  }

  Future<void> _delete() async {
    final password = TextEditingController();
    final session = AppScope.of(context).session;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Seus dados pessoais serão apagados. Os pedidos ficam na loja sem o seu nome. Não dá para desfazer.'),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Confirme sua senha')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await session.deleteAccount(password.text);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    password.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final user = session.user;
    final store = _store;
    return Scaffold(
      appBar: AppBar(title: const Text('Conta')),
      body: ListView(children: [
        if (user == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: const Text('Entrar ou criar conta'),
            ),
          )
        else ...[
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(user.name),
            subtitle: Text(user.email),
            trailing: const Icon(Icons.edit_rounded),
            onTap: _editProfile,
          ),
          ListTile(leading: const Icon(Icons.lock_rounded), title: const Text('Trocar senha'), onTap: _changePassword),
          if (!user.isTeam && Push.configured)
            SwitchListTile(
              secondary: const Icon(Icons.local_offer_rounded),
              title: const Text('Avisos de promoções'),
              value: _promos,
              onChanged: (v) async {
                setState(() => _promos = v);
                try {
                  await Push.setPromotions(session, v);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
        ],
        if (store != null) ...[
          const Divider(),
          ListTile(title: Text(store.name, style: Theme.of(context).textTheme.titleMedium)),
          if (store.pickupAddress != null)
            ListTile(leading: const Icon(Icons.storefront_rounded), title: Text(store.pickupAddress!)),
          if (store.whatsapp != null)
            ListTile(
              leading: const Icon(Icons.chat_rounded),
              title: const Text('Falar com a loja no WhatsApp'),
              onTap: () => launchUrl(whatsappUri(store.whatsapp!), mode: LaunchMode.externalApplication),
            ),
          if (store.instagram != null)
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text('@${store.instagram!.replaceAll('@', '')}'),
              onTap: () => launchUrl(Uri.parse('https://instagram.com/${store.instagram!.replaceAll('@', '')}'),
                  mode: LaunchMode.externalApplication),
            ),
        ],
        if (user != null) ...[
          const Divider(),
          ListTile(leading: const Icon(Icons.logout_rounded), title: const Text('Sair'), onTap: () => session.logout()),
          ListTile(
            leading: const Icon(Icons.devices_rounded),
            title: const Text('Sair de todos os aparelhos'),
            onTap: () async {
              if (await confirm(context, 'Sair de todos os aparelhos?', 'Você vai precisar entrar de novo em cada celular.')) {
                await session.logout(everywhere: true);
              }
            },
          ),
          if (!user.isOwner)
            ListTile(
              leading: Icon(Icons.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
              title: Text('Excluir minha conta', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: _delete,
            ),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}
