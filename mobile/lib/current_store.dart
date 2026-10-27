import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Loja aberta no app do cliente (a plataforma tem várias). Guarda a atual e as últimas visitadas.
///
/// Build "de uma loja só" (app com a marca do lojista): `--dart-define=STORE_SLUG=minha-loja` fixa a loja e
/// esconde a troca.
class CurrentStore extends ChangeNotifier {
  static const fixedSlug = String.fromEnvironment('STORE_SLUG');
  static const _key = 'store.current.v1';
  static const _recentKey = 'store.recent.v1';
  static const _maxRecent = 8;

  StoreCard? _store;
  final List<StoreCard> _recent = [];

  StoreCard? get store => _store;

  String? get slug => _store?.slug;

  List<StoreCard> get recent => List.unmodifiable(_recent);

  bool get fixed => fixedSlug.isNotEmpty;

  /// Caminho das rotas públicas da loja atual.
  String get publicBase => '/api/public/stores/${_store!.slug}';

  /// Caminho das compras (cliente logado) na loja atual.
  String get ordersBase => '/api/stores/${_store!.slug}/orders';

  Future<void> load() async {
    if (fixed) {
      _store = const StoreCard(slug: fixedSlug, name: '');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) _store = StoreCard.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final recent = prefs.getString(_recentKey);
      if (recent != null) {
        _recent
          ..clear()
          ..addAll((jsonDecode(recent) as List).map((e) => StoreCard.fromJson(e as Map<String, dynamic>)));
      }
    } catch (_) {
      // preferências antigas/corrompidas: começa escolhendo a loja
    }
  }

  void open(StoreCard store) {
    _store = store;
    _recent
      ..removeWhere((s) => s.slug == store.slug)
      ..insert(0, store);
    if (_recent.length > _maxRecent) _recent.removeRange(_maxRecent, _recent.length);
    notifyListeners();
    _save();
  }

  /// Nome chegou da API (build de loja fixa começa só com o endereço).
  void rename(String name) {
    final s = _store;
    if (s == null || s.name == name) return;
    _store = StoreCard(slug: s.slug, name: name, instagram: s.instagram);
    notifyListeners();
  }

  /// Volta para a escolha de loja.
  void leave() {
    if (fixed) return;
    _store = null;
    notifyListeners();
    _save();
  }

  void _save() {
    SharedPreferences.getInstance().then((p) async {
      final s = _store;
      if (s == null) {
        await p.remove(_key);
      } else {
        await p.setString(_key, jsonEncode(s.toJson()));
      }
      await p.setString(_recentKey, jsonEncode(_recent.map((r) => r.toJson()).toList()));
    }).catchError((Object _) {});
  }
}
