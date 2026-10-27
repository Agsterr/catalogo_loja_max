import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  GeoPoint? _near;

  /// Raio da busca em km (nulo = sem limite, só ordena pela distância).
  double? _radius = 20;
  String? _city;
  bool _locating = false;
  List<CityCount> _cities = const [];

  static const _cityPref = 'store_picker_city';

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/public/store-cities').then((j) {
      if (mounted) setState(() => _cities = (j as List).map((c) => CityCount.fromJson(c as Map<String, dynamic>)).toList());
    }).catchError((_) {});
    SharedPreferences.getInstance().then((p) {
      final saved = p.getString(_cityPref);
      if (saved != null && mounted) _apply(city: saved);
    }).catchError((_) {});
  }

  void _apply({String? city, GeoPoint? near, bool clearCity = false, bool clearNear = false}) {
    setState(() {
      if (clearCity) _city = null;
      if (clearNear) _near = null;
      _city = city ?? _city;
      _near = near ?? _near;
      _key = GlobalKey();
    });
    SharedPreferences.getInstance().then((p) => _city == null ? p.remove(_cityPref) : p.setString(_cityPref, _city!)).catchError((_) => false);
  }

  Future<void> _toggleNear() async {
    if (_near != null) return _apply(clearNear: true);
    setState(() => _locating = true);
    try {
      _apply(near: await currentPosition());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

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
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: _locating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.near_me_rounded, size: 18),
                    label: const Text('Perto de mim'),
                    selected: _near != null,
                    onSelected: _locating ? null : (_) => _toggleNear(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: const Text('Todas as cidades'), selected: _city == null, onSelected: (_) => _apply(clearCity: true)),
                ),
                for (final c in _cities)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${c.city}${c.state == null ? '' : ' - ${c.state}'} (${c.total})'),
                      selected: _city == c.city,
                      onSelected: (_) => _apply(city: c.city),
                    ),
                  ),
              ],
            ),
          ),
          if (_near != null)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                children: [
                  const Padding(padding: EdgeInsets.only(right: 8, top: 8), child: Text('Até')),
                  for (final km in const [5.0, 10.0, 20.0, 50.0, null])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(km == null ? 'Sem limite' : '${km.toInt()} km'),
                        selected: _radius == km,
                        onSelected: (_) => setState(() {
                          _radius = km;
                          _key = GlobalKey();
                        }),
                      ),
                    ),
                ],
              ),
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
                  await widget.api.get('/api/public/stores?${Uri(queryParameters: {
                    'page': '$page',
                    'q': _q,
                    'city': ?_city,
                    if (_near != null) ...{'lat': '${_near!.lat}', 'lng': '${_near!.lng}', if (_radius != null) 'radiusKm': '${_radius!.toInt()}'},
                  }).query}')
                      as Map<String, dynamic>,
                  StoreCard.fromJson),
              empty: const EmptyState(icon: Icons.storefront_outlined, text: 'Nenhuma loja encontrada.'),
              itemBuilder: (context, s) => Card(
                child: ListTile(
                  leading: StoreLogo(name: s.name, url: s.logoUrl),
                  title: Text(s.name),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (s.description != null) Text(s.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (s.place != null || s.distanceKm != null)
                      Text([if (s.distanceKm != null) '${s.distanceKm!.toStringAsFixed(1).replaceAll('.', ',')} km', ?s.place].join(' · '),
                          style: t.bodySmall),
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
