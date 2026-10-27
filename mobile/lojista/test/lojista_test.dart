import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:loja_core/loja_core.dart';
import 'package:loja_lojista/screens/promotions_screen.dart';
import 'package:loja_lojista/screens/store_orders_screen.dart';

ApiClient _api(Map<String, Object> routes) => ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((req) async {
        final body = routes[req.url.path];
        return http.Response(jsonEncode(body ?? {'detail': 'Não encontrado.'}), body == null ? 404 : 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('pedidos da loja: lista os em aberto com cliente e status', (tester) async {
    final api = _api({
      '/api/store/orders': {
        'items': [
          {
            'id': 1, 'code': 'R8T2KC', 'status': 'PENDING', 'statusLabel': '', 'deliveryMethod': 'DELIVERY', 'paid': false,
            'total': 319.9, 'itemCount': 1, 'customerName': 'Beatriz Lima', 'firstItem': 'Bota', 'thumbUrl': null,
            'createdAt': '2026-10-27T10:00:00',
          },
        ],
        'page': 0, 'size': 20, 'total': 1, 'hasMore': false,
      },
    });
    await tester.pumpWidget(MaterialApp(home: StoreOrdersScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Beatriz Lima'), findsOneWidget);
    expect(find.text('Aguardando confirmação'), findsWidgets);
  });

  testWidgets('promoção de um produto só: escolhe o produto na busca', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _api({
      '/api/store/promotions': [],
      '/api/store/categories': [],
      '/api/store/products': {
        'items': [
          {
            'id': 6, 'name': 'Relógio Minimalista', 'department': 'BIJUTERIAS', 'brand': null, 'price': 159.9,
            'finalPrice': 159.9, 'discountPercent': 0, 'thumbUrl': null, 'inStock': true, 'featured': false,
            'totalStock': 4, 'active': true,
          },
        ],
        'page': 0, 'size': 30, 'total': 1, 'hasMore': false,
      },
    });
    await tester.pumpWidget(MaterialApp(home: PromotionsScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promoção'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Só um produto'));
    await tester.pumpAndSettle();
    expect(find.text('Vale para'), findsNothing); // departamento/categoria somem
    await tester.tap(find.text('Escolher produto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relógio Minimalista'));
    await tester.pumpAndSettle();
    expect(find.text('Relógio Minimalista'), findsOneWidget);
  });
}
