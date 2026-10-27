import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:loja_core/loja_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Item do carrinho. Nome, preço e foto são só para mostrar: o preço que vale é o que o servidor calcula no pedido.
class CartItem {
  CartItem({
    required this.variantId,
    required this.productId,
    required this.name,
    required this.variant,
    required this.unitPrice,
    required this.quantity,
    this.thumbUrl,
    required this.maxStock,
  });

  final int variantId;
  final int productId;
  final String name;
  final String variant;
  double unitPrice;
  int quantity;
  final String? thumbUrl;
  int maxStock;

  double get total => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'variantId': variantId,
        'productId': productId,
        'name': name,
        'variant': variant,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'thumbUrl': thumbUrl,
        'maxStock': maxStock,
      };

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        variantId: j['variantId'] as int,
        productId: j['productId'] as int,
        name: j['name'] as String,
        variant: j['variant'] as String,
        unitPrice: (j['unitPrice'] as num).toDouble(),
        quantity: j['quantity'] as int,
        thumbUrl: j['thumbUrl'] as String?,
        maxStock: j['maxStock'] as int,
      );
}

/// Carrinho guardado no aparelho (sobrevive a fechar o app). É de uma loja só ([storeSlug]): o pedido vai
/// para uma loja.
class Cart extends ChangeNotifier {
  static const _key = 'cart.v2';
  static const maxPerItem = 20;

  final List<CartItem> _items = [];

  /// Loja dos itens (nulo = vazio).
  String? storeSlug;

  List<CartItem> get items => List.unmodifiable(_items);

  int get count => _items.fold(0, (n, i) => n + i.quantity);

  double get subtotal => _items.fold(0, (t, i) => t + i.total);

  bool get isEmpty => _items.isEmpty;

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      storeSlug = json['store'] as String?;
      _items
        ..clear()
        ..addAll((json['items'] as List).map((e) => CartItem.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {
      // carrinho antigo/corrompido: começa vazio
    }
  }

  /// Tem itens de outra loja (adicionar aqui troca o carrinho).
  bool fromOtherStore(String slug) => _items.isNotEmpty && storeSlug != slug;

  /// Soma ao que já tinha do mesmo tamanho/cor, sem passar do estoque. Item de outra loja limpa o carrinho antes.
  void add(CartItem item, {required String store}) {
    if (storeSlug != store) {
      _items.clear();
      storeSlug = store;
    }
    final existing = _items.where((i) => i.variantId == item.variantId).firstOrNull;
    final limit = item.maxStock.clamp(1, maxPerItem);
    if (existing != null) {
      existing.quantity = (existing.quantity + item.quantity).clamp(1, limit);
    } else {
      item.quantity = item.quantity.clamp(1, limit);
      _items.add(item);
    }
    _changed();
  }

  /// Aplica o que a loja respondeu na conferência do carrinho: tira o que saiu de venda, reduz ao estoque e atualiza o
  /// preço de agora. Devolve o que mudou, em frases, para avisar a pessoa antes de fechar.
  List<String> applyQuote(List<QuoteLine> lines) {
    final notes = <String>[];
    for (final line in lines) {
      final item = _items.where((i) => i.variantId == line.variantId).firstOrNull;
      if (item == null) continue;
      if (!line.available || line.stock == 0) {
        _items.remove(item);
        notes.add('${item.name} (${item.variant}) saiu de venda ou esgotou e foi tirado do carrinho.');
        continue;
      }
      if (line.quantity < item.quantity) {
        notes.add('${item.name} (${item.variant}): só restam ${line.stock}.');
        item.quantity = line.quantity;
      }
      item.maxStock = line.stock;
      final price = line.unitPrice;
      if (price != null && (price - item.unitPrice).abs() > 0.004) {
        notes.add('${item.name}: o preço mudou de ${_money(item.unitPrice)} para ${_money(price)}.');
        item.unitPrice = price;
      }
    }
    if (_items.isEmpty) storeSlug = null;
    if (notes.isNotEmpty || lines.isNotEmpty) _changed();
    return notes;
  }

  static String _money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  void setQuantity(int variantId, int quantity) {
    final item = _items.where((i) => i.variantId == variantId).firstOrNull;
    if (item == null) return;
    if (quantity <= 0) {
      _items.remove(item);
      if (_items.isEmpty) storeSlug = null;
    } else {
      item.quantity = quantity.clamp(1, item.maxStock.clamp(1, maxPerItem));
    }
    _changed();
  }

  void clear() {
    _items.clear();
    storeSlug = null;
    _changed();
  }

  void _changed() {
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, jsonEncode({'store': storeSlug, 'items': _items.map((i) => i.toJson()).toList()})))
        .catchError((Object _) => false);
  }
}
