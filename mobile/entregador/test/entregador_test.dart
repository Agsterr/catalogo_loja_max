import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:loja_core/loja_core.dart';
import 'package:loja_entregador/courier_api.dart';
import 'package:loja_entregador/screens/active_screen.dart';
import 'package:loja_entregador/screens/board_screen.dart';
import 'package:loja_entregador/screens/register_screen.dart';

/// API simulada: `routes` devolve (status, corpo) para "MÉTODO /caminho"; `calls` guarda o que o app chamou.
CourierApi _api(Map<String, (int, Object)> routes, List<String> calls) => CourierApi(ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((req) async {
        final key = '${req.method} ${req.url.path}';
        calls.add(req.method == 'POST' ? '$key ${req.body}' : key);
        final r = routes[key];
        return http.Response(jsonEncode(r?.$2 ?? {'detail': 'Não encontrado.'}), r?.$1 ?? 404,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    ));

CourierProfile _profile() => const CourierProfile(
    id: 1, name: 'Zé Moto', email: 'ze@x.com', phone: '11988887777', vehicle: 'MOTO', city: 'Campinas', state: 'SP',
    radiusKm: 10, status: 'APPROVED', online: true, deliveredCount: 3, canceledCount: 0);

Map<String, dynamic> _card(int id) => {
      'id': id, 'storeName': 'Moda da Ana', 'pickupAddress': 'Rua das Flores, 120', 'city': 'Campinas', 'distanceToStoreKm': 1.2,
      'tripKm': 3.5, 'fee': 9.25, 'itemCount': 2, 'createdAt': '2026-10-27T10:00:00',
      'expiresAt': DateTime.now().add(const Duration(minutes: 25)).toIso8601String().substring(0, 19),
    };

Map<String, dynamic> _job({String status = 'ACCEPTED'}) => {
      'id': 5, 'orderCode': 'K7Q2MD', 'status': status, 'statusLabel': 'a caminho', 'storeName': 'Moda da Ana',
      'pickupAddress': 'Rua das Flores, 120', 'pickupLat': -22.9, 'pickupLng': -47.06, 'dropoffAddress': 'Av. Brasil, 500 - Centro',
      'dropoffLat': -22.91, 'dropoffLng': -47.07, 'customerName': 'Carla Souza', 'customerPhone': '11999990000', 'tripKm': 3.5,
      'fee': 9.25, 'itemCount': 2, 'acceptedAt': '2026-10-27T10:05:00', 'pickedUpAt': null, 'deliveredAt': null,
    };

Map<String, dynamic> _page(List<Object> items) => {'items': items, 'page': 0, 'size': 20, 'total': items.length, 'hasMore': false};

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('mural: lista a corrida com valor e aceitar leva ao passo a passo; 409 avisa que outro pegou', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    var accepted = false;
    final api = _api({
      'GET /api/courier/jobs/open': (200, _page([_card(5)])),
      'POST /api/courier/jobs/5/accept': (409, {'detail': 'Essa corrida não está mais disponível.'}),
    }, calls);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BoardScreen(
          api: api,
          profile: _profile(),
          onProfile: (_) {},
          onAccepted: () => accepted = true,
          locate: () async => const GeoPoint(-22.9, -47.06),
          visible: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Moda da Ana'), findsOneWidget);
    expect(find.textContaining('9,25'), findsOneWidget);
    expect(find.textContaining('a 1,2 km de você'), findsOneWidget);
    expect(calls.first, contains('GET /api/courier/jobs/open'));

    await tester.tap(find.text('Moda da Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Aceitar corrida'), findsOneWidget);
    expect(find.textContaining('endereço do cliente aparece depois'), findsOneWidget);
    await tester.tap(find.text('Aceitar corrida'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Outro entregador pegou'), findsOneWidget);
    expect(accepted, isFalse);
  });

  testWidgets('em andamento: pede o código de coleta e depois o de entrega', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    var picked = false;
    final api = CourierApi(ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((req) async {
        final key = '${req.method} ${req.url.path}';
        calls.add(req.method == 'POST' ? '$key ${req.body}' : key);
        if (key == 'POST /api/courier/jobs/5/pickup') picked = true;
        final job = _job(status: picked ? 'PICKED_UP' : 'ACCEPTED');
        final body = key == 'GET /api/courier/jobs/active' ? [job] : (key == 'POST /api/courier/jobs/5/pickup' ? job : null);
        return http.Response(jsonEncode(body ?? {'detail': 'x'}), body == null ? 404 : 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    ));
    var count = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ActiveScreen(api: api, onCount: (n) => count = n, onChanged: () {})),
    ));
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(find.text('1. Vá até a loja'), findsOneWidget);
    expect(find.text('Código de coleta (peça à loja)'), findsOneWidget);
    expect(find.text('Desistir da corrida'), findsOneWidget);
    expect(find.textContaining('Av. Brasil'), findsNothing); // o cliente só aparece depois da coleta

    await tester.enterText(find.byType(TextField), '4821');
    await tester.tap(find.text('Confirmar coleta'));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/courier/jobs/5/pickup {"code":"4821"}'));
    expect(find.text('2. Entregue ao cliente'), findsOneWidget);
    expect(find.textContaining('Av. Brasil, 500'), findsOneWidget);
    expect(find.text('Código de entrega (peça ao cliente)'), findsOneWidget);
    expect(find.text('Desistir da corrida'), findsNothing); // depois de coletar não desiste
  });

  testWidgets('cadastro: valida os campos antes de enviar', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    final session = Session(
        httpClient: MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      return http.Response('{}', 200);
    }));
    await tester.pumpWidget(MaterialApp(home: RegisterCourierScreen(session: session)));
    await tester.scrollUntilVisible(find.text('Enviar cadastro'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Enviar cadastro'));
    await tester.pumpAndSettle();
    expect(find.text('Informe seu nome'), findsOneWidget);
    expect(find.text('E-mail inválido'), findsOneWidget);
    expect(find.text('Informe a cidade'), findsOneWidget);
    expect(calls.where((c) => c.contains('register-courier')), isEmpty);
  });

  test('tempo até expirar', () {
    final now = DateTime(2026, 10, 27, 10);
    expect(expiresIn(now.add(const Duration(minutes: 23, seconds: 30)), now: now), 'expira em 23 min');
    expect(expiresIn(now.add(const Duration(seconds: 20)), now: now), 'expira em instantes');
    expect(expiresIn(now.add(const Duration(hours: 2)), now: now), 'expira em 2 h');
  });
}
