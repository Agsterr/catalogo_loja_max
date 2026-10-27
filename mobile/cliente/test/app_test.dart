import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:loja_cliente/app_scope.dart';
import 'package:loja_cliente/cart.dart';
import 'package:loja_cliente/current_store.dart';
import 'package:loja_cliente/screens/catalog_screen.dart';
import 'package:loja_cliente/screens/product_screen.dart';
import 'package:loja_core/loja_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _card(int id, String name, {double price = 100, double? finalPrice, int discount = 0}) => {
      'id': id,
      'name': name,
      'department': 'ROUPAS',
      'brand': null,
      'price': price,
      'finalPrice': finalPrice ?? price,
      'discountPercent': discount,
      'thumbUrl': null,
      'inStock': true,
      'featured': false,
      'totalStock': 5,
      'active': true,
    };

Map<String, dynamic> _product() => {
      'id': 7,
      'name': 'Vestido Midi',
      'description': 'Viscose',
      'department': 'ROUPAS',
      'categoryId': null,
      'categoryName': null,
      'brand': 'Max',
      'price': 200,
      'salePrice': null,
      'finalPrice': 150,
      'discountPercent': 25,
      'promotion': 'Semana da moda',
      'minStock': 1,
      'active': true,
      'featured': false,
      'totalStock': 3,
      'variants': [
        {'id': 70, 'size': 'P', 'color': 'Preto', 'sku': null, 'stock': 0, 'active': true},
        {'id': 71, 'size': 'M', 'color': 'Preto', 'sku': null, 'stock': 3, 'active': true},
      ],
      'photos': [],
      'createdAt': '2026-10-01T10:00:00',
    };

ApiClient _api() => ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((req) async {
        final path = req.url.path;
        Object body = switch (path) {
          '/api/public/stores/moda/categories' => [],
          '/api/public/stores/moda/promotions' => [],
          '/api/public/stores/moda/products' => {
              'items': [_card(1, 'Tênis Runner', price: 200, finalPrice: 150, discount: 25), _card(2, 'Brinco Argola')],
              'page': 0,
              'size': 20,
              'total': 2,
              'hasMore': false,
            },
          '/api/public/stores/moda/products/7' => _product(),
          _ => {'detail': 'Não encontrado.'},
        };
        return http.Response(jsonEncode(body), body is Map && body.containsKey('detail') ? 404 : 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

Widget _app(Widget child, Cart cart) =>
    AppScope(session: Session(), cart: cart, store: CurrentStore(), child: MaterialApp(home: child));

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('carrinho soma o mesmo tamanho e respeita o estoque', () {
    final cart = Cart();
    CartItem item(int qty) => CartItem(
        variantId: 1, productId: 1, name: 'Tênis', variant: '38', unitPrice: 99.9, quantity: qty, maxStock: 3);
    cart.add(item(2), store: 'moda');
    cart.add(item(2), store: 'moda');
    expect(cart.count, 3);
    expect(cart.subtotal, closeTo(299.7, 0.001));
    // peça de outra loja: o carrinho troca (cada pedido é de uma loja)
    expect(cart.fromOtherStore('outra'), isTrue);
    cart.add(item(1), store: 'outra');
    expect(cart.storeSlug, 'outra');
    expect(cart.count, 1);
    cart.setQuantity(1, 0);
    expect(cart.isEmpty, isTrue);
    expect(cart.storeSlug, isNull);
  });

  test('pedido da API vira modelo com linha do tempo', () {
    final order = Order.fromJson({
      'id': 1,
      'code': 'K7Q2MD',
      'status': 'READY',
      'nextStatuses': ['DELIVERED', 'CANCELED'],
      'canCancel': false,
      'deliveryMethod': 'PICKUP',
      'paymentMethod': 'PIX',
      'paid': true,
      'subtotal': 450,
      'discount': 150,
      'deliveryFee': 0,
      'total': 450,
      'createdAt': '2026-10-27T10:00:00',
      'updatedAt': '2026-10-27T11:00:00',
      'customer': null,
      'items': [
        {'productId': 1, 'variantId': 2, 'productName': 'Tênis', 'size': '37', 'color': 'Preto', 'unitPrice': 150, 'quantity': 3, 'total': 450}
      ],
      'events': [
        {'status': 'PENDING', 'label': 'x', 'note': null, 'byCustomer': true, 'createdAt': '2026-10-27T10:00:00'},
        {'status': 'READY', 'label': 'x', 'note': null, 'byCustomer': false, 'createdAt': '2026-10-27T11:00:00'},
      ],
    });
    expect(order.status, OrderStatus.ready);
    expect(order.nextStatuses, [OrderStatus.delivered, OrderStatus.canceled]);
    expect(order.items.single.variant, '37 · Preto');
    expect(order.events.last.byCustomer, isFalse);
  });

  test('formatação e regras locais', () {
    expect(money(1234.5), contains('1.234,50'));
    expect(whatsappUri('(11) 99999-0000').toString(), 'https://wa.me/5511999990000');
    expect(passwordProblem('12345678'), isNotNull);
    expect(passwordProblem('Senha1234'), isNull);
    expect(payloadFor(orderIdText: '12', slug: 'moda'), 'order:12@moda');
    final target = parsePayload('product:5@moda-da-ana')!;
    expect((target.kind, target.id, target.slug), ('product', 5, 'moda-da-ana'));
    expect(parsePayload('order:3')!.slug, isNull);
    expect(slugify('Moda da Ána & Cia'), 'moda-da-ana-cia');
    expect(LocalNotifications.idFor('a'), LocalNotifications.idFor('a'));
  });

  testWidgets('vitrine mostra produtos e preço de promoção', (tester) async {
    await tester.pumpWidget(_app(CatalogScreen(api: _api(), slug: 'moda', storeName: 'Moda da Ana'), Cart()));
    await tester.pumpAndSettle();
    expect(find.text('Tênis Runner'), findsOneWidget);
    expect(find.text('Brinco Argola'), findsOneWidget);
    expect(find.text('-25%'), findsOneWidget);
    expect(find.text('Calçados'), findsOneWidget);
    expect(find.text('Moda da Ana'), findsOneWidget);
  });

  testWidgets('produto: tamanho esgotado fica desligado e o disponível vai para o carrinho', (tester) async {
    // tela alta: a foto quadrada não empurra o resto para fora da lista
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cart = Cart();
    await tester.pumpWidget(_app(ProductScreen(api: _api(), slug: 'moda', productId: 7), cart));
    await tester.pumpAndSettle();
    expect(find.text('Vestido Midi'), findsOneWidget);
    expect(find.textContaining('25% off'), findsOneWidget);
    // só o M tem estoque: já vem escolhido
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();
    expect(cart.count, 1);
    expect(cart.items.single.variant, 'M · Preto');
    expect(cart.items.single.unitPrice, 150);
    expect(cart.storeSlug, 'moda');
  });
}
