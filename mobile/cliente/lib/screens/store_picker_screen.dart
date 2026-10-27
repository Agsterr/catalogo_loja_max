import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import '../app_scope.dart';

/// Escolha da loja (a plataforma tem várias): busca pelo nome e lojas visitadas por último.
class StorePickerScreen extends StatefulWidget {
  const StorePickerScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<StorePickerScreen> createState() => _StorePickerScreenState();
}

class _StorePickerScreenState extends State<StorePickerScreen> {
  String _q = '';
  Timer? _debounce;
  var _key = GlobalKey<PagedListState<StoreCard>>();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final recent = scope.store.recent;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.brand, AppTheme.sale], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 8),
                Text('Loja Max', style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (!scope.session.signedIn)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(session: AppScope.of(context).session))),
                    child: const Text('Entrar'),
                  ),
              ]),
              const SizedBox(height: 8),
              Text('Roupas, calçados e bijuterias das lojas da sua cidade.',
                  style: t.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar loja pelo nome',
                  prefixIcon: const Icon(Icons.search_rounded),
                  fillColor: Theme.of(context).colorScheme.surface,
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () => setState(() {
                        _q = v.trim();
                        _key = GlobalKey();
                      }));
                },
              ),
            ]),
          ),
          if (recent.isNotEmpty && _q.isEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                children: [
                  for (final s in recent)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.history_rounded, size: 18),
                        label: Text(s.name),
                        onPressed: () => scope.store.open(s),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: PagedList<StoreCard>(
              key: _key,
              load: (page) async => PageResult.fromJson(
                  await widget.api.get('/api/public/stores?${Uri(queryParameters: {'page': '$page', 'q': _q}).query}')
                      as Map<String, dynamic>,
                  StoreCard.fromJson),
              empty: const EmptyState(icon: Icons.storefront_outlined, text: 'Nenhuma loja encontrada.'),
              itemBuilder: (context, s) => Card(
                child: ListTile(
                  leading: StoreLogo(name: s.name, url: s.logoUrl),
                  title: Text(s.name),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (s.description != null) Text(s.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    OpenBadge(s.status),
                    if (s.description == null && s.status == null && s.instagram != null) Text('@${s.instagram!.replaceAll('@', '')}'),
                  ]),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => scope.store.open(s),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
