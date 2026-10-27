import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  final double unitPrice;
  int quantity;
  final String? thumbUrl;
  final int maxStock;

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

/// Carrinho guardado no aparelho (sobrevive a fechar o app).
class Cart extends ChangeNotifier {
  static const _key = 'cart.v1';
  static const maxPerItem = 20;

  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get count => _items.fold(0, (n, i) => n + i.quantity);

  double get subtotal => _items.fold(0, (t, i) => t + i.total);

  bool get isEmpty => _items.isEmpty;

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      _items
        ..clear()
        ..addAll((jsonDecode(raw) as List).map((e) => CartItem.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {
      // carrinho antigo/corrompido: começa vazio
    }
  }

  /// Soma ao que já tinha do mesmo tamanho/cor, sem passar do estoque.
  void add(CartItem item) {
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

  void setQuantity(int variantId, int quantity) {
    final item = _items.where((i) => i.variantId == variantId).firstOrNull;
    if (item == null) return;
    if (quantity <= 0) {
      _items.remove(item);
    } else {
      item.quantity = quantity.clamp(1, item.maxStock.clamp(1, maxPerItem));
    }
    _changed();
  }

  void clear() {
    _items.clear();
    _changed();
  }

  void _changed() {
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, jsonEncode(_items.map((i) => i.toJson()).toList())))
        .catchError((Object _) => false);
  }
}
