import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';
import 'admin_screens.dart';
import 'plan_screen.dart';
import 'promotions_screen.dart';
import 'report_screen.dart';

/// Menu da gestão. Resumo, promoções, equipe e dados da loja são só do dono (a API também confere).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final owner = session.user?.isOwner ?? false;
    final api = session.api;
    void go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: Text(session.user?.storeName ?? 'Mais')),
      body: ListView(children: [
        if (owner) ...[
          ListTile(leading: const Icon(Icons.insights_rounded), title: const Text('Resumo de vendas'), onTap: () => go(ReportScreen(api: api))),
          ListTile(leading: const Icon(Icons.local_offer_rounded), title: const Text('Promoções'), onTap: () => go(PromotionsScreen(api: api))),
        ],
        ListTile(leading: const Icon(Icons.category_rounded), title: const Text('Categorias'), onTap: () => go(CategoriesScreen(api: api))),
        ListTile(
          leading: const Icon(Icons.people_alt_rounded),
          title: const Text('Clientes'),
          onTap: () => go(CustomersScreen(api: api, canBlock: owner)),
        ),
        if (owner) ...[
          ListTile(leading: const Icon(Icons.badge_rounded), title: const Text('Equipe'), onTap: () => go(TeamScreen(api: api))),
          ListTile(leading: const Icon(Icons.storefront_rounded), title: const Text('Dados da loja'), onTap: () => go(StoreSettingsScreen(api: api))),
          ListTile(
            leading: const Icon(Icons.workspace_premium_rounded),
            title: const Text('Plano e mensalidade'),
            subtitle: const Text('Teste grátis, vencimento e como pagar'),
            onTap: () => go(const PlanScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.policy_rounded),
            title: const Text('Auditoria'),
            subtitle: const Text('Quem entrou e o que mudou'),
            onTap: () => go(SecurityEventsScreen(api: api, store: true)),
          ),
        ],
        const Divider(),
        if (session.user?.storeSlug != null)
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Endereço da loja'),
            subtitle: Text(session.user!.storeSlug!),
          ),
        ListTile(
          leading: const Icon(Icons.person_rounded),
          title: const Text('Minha conta'),
          onTap: () => go(AccountScreen(
            session: session,
            loadStore: () async => StoreInfo.fromJson(await api.get('/api/store/settings') as Map<String, dynamic>),
          )),
        ),
      ]),
    );
  }
}
