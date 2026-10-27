import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';

/// Administrador da plataforma: lojas e contas (bloquear vale na hora, inclusive para quem já estava logado).
class PlatformShell extends StatefulWidget {
  const PlatformShell({super.key});

  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).session.api;
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        _StoresTab(api: api),
        _UsersTab(api: api),
        AccountScreen(session: AppScope.of(context).session),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Lojas'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Conta'),
        ],
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context, String title) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLength: 300, decoration: const InputDecoration(labelText: 'Motivo (a pessoa vê)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bloquear')),
      ],
    ),
  );
  final text = c.text.trim();
  c.dispose();
  return ok == true ? text : null;
}

class _SearchList<T> extends StatefulWidget {
  const _SearchList({required this.title, required this.hint, required this.load, required this.itemBuilder});

  final String title;
  final String hint;
  final Future<PageResult<T>> Function(String q, int page) load;
  final Widget Function(BuildContext, T, VoidCallback refresh) itemBuilder;

  @override
  State<_SearchList<T>> createState() => _SearchListState<T>();
}

class _SearchListState<T> extends State<_SearchList<T>> {
  String _q = '';
  var _key = GlobalKey<PagedListState<T>>();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search_rounded), isDense: true),
                onSubmitted: (v) => setState(() {
                  _q = v.trim();
                  _key = GlobalKey();
                }),
              ),
            ),
          ),
        ),
        body: PagedList<T>(
          key: _key,
          load: (page) => widget.load(_q, page),
          empty: const EmptyState(icon: Icons.search_off_rounded, text: 'Nada encontrado.'),
          separator: const Divider(height: 1),
          padding: EdgeInsets.zero,
          itemBuilder: (context, item) => widget.itemBuilder(context, item, () => _key.currentState?.refresh()),
        ),
      );
}

class _StoresTab extends StatelessWidget {
  const _StoresTab({required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) => _SearchList<Map<String, dynamic>>(
        title: 'Lojas da plataforma',
        hint: 'Nome ou endereço da loja',
        load: (q, page) async => PageResult.fromJson(
            await api.get('/api/platform/stores?${Uri(queryParameters: {'page': '$page', 'q': q}).query}') as Map<String, dynamic>,
            (j) => j),
        itemBuilder: (context, s, refresh) {
          final blocked = s['blocked'] == true;
          return ListTile(
            leading: Icon(blocked ? Icons.block_rounded : Icons.storefront_rounded,
                color: blocked ? Theme.of(context).colorScheme.error : null),
            title: Text(s['name'] as String),
            subtitle: Text([
              s['slug'],
              '${s['products']} produtos · ${s['orders']} pedidos',
              'desde ${date(DateTime.parse(s['createdAt'] as String))}',
              if (blocked) 'bloqueada${s['blockedReason'] != null ? ': ${s['blockedReason']}' : ''}',
            ].join(' · ')),
            trailing: TextButton(
              onPressed: () async {
                try {
                  if (blocked) {
                    await api.post('/api/platform/stores/${s['id']}/unblock');
                  } else {
                    final reason = await _askReason(context, 'Bloquear ${s['name']}?');
                    if (reason == null) return;
                    await api.post('/api/platform/stores/${s['id']}/block', {'reason': reason});
                  }
                  refresh();
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              child: Text(blocked ? 'Desbloquear' : 'Bloquear'),
            ),
          );
        },
      );
}

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.api});

  final ApiClient api;

  static const _roles = {
    Role.owner: 'dono de loja',
    Role.staff: 'funcionário',
    Role.customer: 'cliente',
    Role.platformAdmin: 'admin',
  };

  @override
  Widget build(BuildContext context) => _SearchList<User>(
        title: 'Contas',
        hint: 'Nome ou e-mail',
        load: (q, page) async => PageResult.fromJson(
            await api.get('/api/platform/users?${Uri(queryParameters: {'page': '$page', 'q': q}).query}') as Map<String, dynamic>,
            User.fromJson),
        itemBuilder: (context, u, refresh) => ListTile(
          leading: Icon(u.blocked ? Icons.block_rounded : Icons.person_rounded,
              color: u.blocked ? Theme.of(context).colorScheme.error : null),
          title: Text(u.name),
          subtitle: Text('${u.email} · ${_roles[u.role]}${u.twoFactorEnabled ? ' · duas etapas' : ''}'),
          trailing: u.isPlatformAdmin
              ? null
              : PopupMenuButton<String>(
                  onSelected: (action) async {
                    try {
                      switch (action) {
                        case 'block':
                          final reason = await _askReason(context, 'Bloquear ${u.name}?');
                          if (reason == null) return;
                          await api.post('/api/platform/users/${u.id}/block', {'reason': reason});
                        case 'unblock':
                          await api.post('/api/platform/users/${u.id}/unblock');
                        case '2fa':
                          await api.post('/api/platform/users/${u.id}/reset-2fa');
                          if (context.mounted) showInfo(context, 'Verificação em duas etapas desligada.');
                      }
                      refresh();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: u.blocked ? 'unblock' : 'block', child: Text(u.blocked ? 'Desbloquear' : 'Bloquear')),
                    if (u.twoFactorEnabled) const PopupMenuItem(value: '2fa', child: Text('Desligar duas etapas (perdeu o celular)')),
                  ],
                ),
        ),
      );
}
