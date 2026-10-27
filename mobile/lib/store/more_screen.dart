import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../screens/account_screen.dart';
import 'admin_screens.dart';
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
      appBar: AppBar(title: Text(session.user?.name ?? 'Mais')),
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
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.person_rounded),
          title: const Text('Minha conta'),
          onTap: () => go(const AccountScreen()),
        ),
      ]),
    );
  }
}
