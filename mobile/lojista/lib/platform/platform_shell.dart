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
        _CouriersTab(api: api),
        _UsersTab(api: api),
        AccountScreen(session: AppScope.of(context).session),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Lojas'),
          NavigationDestination(icon: Icon(Icons.two_wheeler_outlined), selectedIcon: Icon(Icons.two_wheeler), label: 'Entregadores'),
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
    Role.courier: 'entregador',
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

/// Entregadores: aprovar cadastros novos e bloquear quem não deve mais entregar.
class _CouriersTab extends StatefulWidget {
  const _CouriersTab({required this.api});

  final ApiClient api;

  @override
  State<_CouriersTab> createState() => _CouriersTabState();
}

class _CouriersTabState extends State<_CouriersTab> {
  static const _filters = {'PENDING': 'Em análise', 'APPROVED': 'Aprovados', 'BLOCKED': 'Bloqueados', 'PAYMENTS': 'Assinaturas'};

  String _status = 'PENDING';
  var _key = GlobalKey<PagedListState<AdminCourier>>();

  Future<void> _act(AdminCourier c, bool approve) async {
    try {
      if (approve) {
        await widget.api.post('/api/platform/couriers/${c.id}/approve');
      } else {
        final reason = await _askReason(context, 'Bloquear ${c.name}?');
        if (reason == null) return;
        await widget.api.post('/api/platform/couriers/${c.id}/block', {'reason': reason});
      }
      _key.currentState?.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Cortesia: libera dias de assinatura sem cobrança.
  Future<void> _grant(AdminCourier c) async {
    final days = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dar assinatura a ${c.name}'),
        content: TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Dias', suffixText: 'dias')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Liberar')),
        ],
      ),
    );
    final n = int.tryParse(days.text.trim());
    days.dispose();
    if (ok != true || n == null || n < 1 || n > 366) return;
    try {
      await widget.api.post('/api/platform/couriers/${c.id}/grant', {'days': n});
      if (mounted) showInfo(context, 'Assinatura liberada por $n dias.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Entregadores'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: SizedBox(
              height: 52,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (_) => setState(() {
                        _status = e.key;
                        _key = GlobalKey();
                      }),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        body: _status == 'PAYMENTS' ? _PaymentsList(api: widget.api, onChanged: () {}) : PagedList<AdminCourier>(
          key: _key,
          load: (page) async => PageResult.fromJson(
              await widget.api.get('/api/platform/couriers?${Uri(queryParameters: {'page': '$page', 'status': _status}).query}')
                  as Map<String, dynamic>,
              AdminCourier.fromJson),
          empty: const EmptyState(icon: Icons.two_wheeler_rounded, text: 'Nenhum entregador nesta lista.'),
          separator: const Divider(height: 1),
          padding: EdgeInsets.zero,
          itemBuilder: (context, c) => ListTile(
            leading: Icon(c.status == 'BLOCKED' ? Icons.block_rounded : Icons.two_wheeler_rounded,
                color: c.status == 'BLOCKED' ? Theme.of(context).colorScheme.error : null),
            title: Text(c.name),
            subtitle: Text([
              '${vehicleLabels[c.vehicle] ?? c.vehicle}${c.plate == null ? '' : ' ${c.plate}'}',
              '${c.city} - ${c.state}',
              c.phone,
              '${c.deliveredCount} entregas',
              if (c.canceledCount > 0) '${c.canceledCount} desistências',
              if (c.statusReason != null) c.statusReason!,
            ].join(' · ')),
            isThreeLine: true,
            trailing: c.status == 'PENDING'
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Bloquear', onPressed: () => _act(c, false), icon: const Icon(Icons.close_rounded)),
                    FilledButton(onPressed: () => _act(c, true), child: const Text('Aprovar')),
                  ])
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (c.status == 'APPROVED')
                      IconButton(
                        tooltip: 'Dar dias de assinatura',
                        onPressed: () => _grant(c),
                        icon: const Icon(Icons.card_giftcard_rounded),
                      ),
                    TextButton(
                      onPressed: () => _act(c, c.status == 'BLOCKED'),
                      child: Text(c.status == 'BLOCKED' ? 'Reativar' : 'Bloquear'),
                    ),
                  ]),
          ),
        ),
      );
}

/// Cobranças de assinatura esperando a confirmação do pagamento (o entregador pagou o Pix da plataforma).
class _PaymentsList extends StatefulWidget {
  const _PaymentsList({required this.api, required this.onChanged});

  final ApiClient api;
  final VoidCallback onChanged;

  @override
  State<_PaymentsList> createState() => _PaymentsListState();
}

class _PaymentsListState extends State<_PaymentsList> {
  final _key = GlobalKey<PagedListState<AdminPayment>>();

  Future<void> _confirm(AdminPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar pagamento?'),
        content: Text('${p.courierName ?? 'Entregador'} · ${money(p.amount)}\nCódigo ${p.reference}\n\nConfira no extrato do Pix antes de confirmar. A assinatura de 30 dias é liberada na hora.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Recebi, liberar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/api/platform/courier-payments/${p.id}/confirm');
      _key.currentState?.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => PagedList<AdminPayment>(
        key: _key,
        load: (page) async => PageResult.fromJson(
            await widget.api.get('/api/platform/courier-payments?${Uri(queryParameters: {'page': '$page'}).query}')
                as Map<String, dynamic>,
            AdminPayment.fromJson),
        empty: const EmptyState(icon: Icons.payments_outlined, text: 'Nenhuma assinatura esperando confirmação.'),
        separator: const Divider(height: 1),
        padding: EdgeInsets.zero,
        itemBuilder: (context, p) => ListTile(
          leading: const Icon(Icons.payments_rounded),
          title: Text('${p.courierName ?? 'Entregador'} · ${money(p.amount)}'),
          subtitle: Text('Código ${p.reference} · ${dateTime(p.createdAt)}'),
          trailing: FilledButton(onPressed: () => _confirm(p), child: const Text('Confirmar')),
        ),
      );
}
