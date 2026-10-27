import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:loja_core/loja_core.dart';
import 'package:loja_entregador/courier_api.dart';
import 'package:loja_entregador/cpf.dart';
import 'package:loja_entregador/freight.dart';
import 'package:loja_entregador/location_reporter.dart';
import 'package:loja_entregador/screens/account_tab.dart';
import 'package:loja_entregador/app_scope.dart';
import 'package:loja_entregador/screens/active_screen.dart';
import 'package:loja_entregador/screens/board_screen.dart';
import 'package:loja_entregador/screens/register_screen.dart';
import 'package:loja_entregador/screens/subscription_screen.dart';

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

Map<String, dynamic> _card(int id, {double bonus = 0}) => {
      'id': id, 'storeName': 'Moda da Ana', 'pickupAddress': 'Rua das Flores, 120', 'city': 'Campinas', 'distanceToStoreKm': 1.2,
      'tripKm': 3.5, 'fee': 9.25, 'bonus': bonus, 'freightPayer': 'CUSTOMER', 'itemCount': 2, 'createdAt': '2026-10-27T10:00:00',
      'expiresAt': DateTime.now().add(const Duration(minutes: 25)).toIso8601String().substring(0, 19),
    };

Map<String, dynamic> _job({String status = 'ACCEPTED', String payer = 'CUSTOMER', double bonus = 0}) => {
      'id': 5, 'orderCode': 'K7Q2MD', 'status': status, 'statusLabel': 'a caminho', 'storeName': 'Moda da Ana',
      'pickupAddress': 'Rua das Flores, 120', 'pickupLat': -22.9, 'pickupLng': -47.06, 'dropoffAddress': 'Av. Brasil, 500 - Centro',
      'dropoffLat': -22.91, 'dropoffLng': -47.07, 'customerName': 'Carla Souza', 'customerPhone': '11999990000', 'tripKm': 3.5,
      'fee': 9.25, 'bonus': bonus, 'freightPayer': payer, 'itemCount': 2, 'acceptedAt': '2026-10-27T10:05:00', 'pickedUpAt': null, 'deliveredAt': null,
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
    expect(find.textContaining('pago pelo cliente'), findsOneWidget);
    expect(calls.any((c) => c.contains('GET /api/courier/jobs/open')), isTrue);

    await tester.tap(find.text('Moda da Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Aceitar corrida'), findsOneWidget);
    expect(find.textContaining('endereço do cliente aparece depois'), findsOneWidget);
    expect(find.text('Frete pago pelo cliente na entrega'), findsOneWidget);
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
    expect(find.text('CPF inválido'), findsOneWidget);
    expect(calls.where((c) => c.contains('register-courier')), isEmpty);
  });

  testWidgets('aceitar sem saldo (402) abre a assinatura com a mensagem', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _api({
      'GET /api/courier/jobs/open': (200, _page([_card(5)])),
      'POST /api/courier/jobs/5/accept': (402, {'detail': 'Suas 5 entregas grátis acabaram.', 'code': 'SUBSCRIPTION_REQUIRED'}),
      'GET /api/courier/subscription': (200, {'subscribed': false, 'paidUntil': null, 'freeLeft': 0, 'freeLimit': 5, 'price': 24.99, 'canAccept': false}),
    }, []);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BoardScreen(api: api, profile: _profile(), onProfile: (_) {}, onAccepted: () {}, locate: () async => null, visible: false),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('entregas grátis acabaram. Assine'), findsOneWidget); // aviso no topo do mural
    await tester.tap(find.text('Moda da Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar corrida'));
    await tester.pumpAndSettle();
    expect(find.text('Assinatura'), findsOneWidget);
    expect(find.text('Suas 5 entregas grátis acabaram.'), findsOneWidget);
    expect(find.text('0 de 5 entregas grátis restantes'), findsOneWidget);
  });

  testWidgets('assinatura: Assinar mostra a chave Pix, o valor e o código de referência', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _api({
      'GET /api/courier/subscription': (200, {'subscribed': false, 'paidUntil': null, 'freeLeft': 3, 'freeLimit': 5, 'price': 24.99, 'canAccept': true}),
      'POST /api/courier/subscription/checkout': (200, {
        'method': 'PIX', 'pixKey': 'pagamentos@lojamax.com.br', 'holder': 'Loja Max Ltda', 'reference': 'ASS-7K2Q', 'amount': 24.99,
        'message': 'Pague e informe o código. A liberação é feita em até 1 dia útil.',
      }),
    }, []);
    await tester.pumpWidget(MaterialApp(home: SubscriptionScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('3 de 5 entregas grátis restantes'), findsOneWidget);
    await tester.tap(find.textContaining('Assinar'));
    await tester.pumpAndSettle();
    expect(find.text('pagamentos@lojamax.com.br'), findsOneWidget);
    expect(find.text('ASS-7K2Q'), findsOneWidget);
    expect(find.textContaining('24,99'), findsWidgets);
    expect(find.byTooltip('Copiar chave'), findsOneWidget);
    expect(find.text('Já paguei, atualizar'), findsOneWidget);
  });

  testWidgets('em andamento: lembra de receber o frete da loja na coleta e do cliente na entrega', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var status = 'ACCEPTED';
    var payer = 'STORE';
    final api = CourierApi(ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((req) async => http.Response(jsonEncode([_job(status: status, payer: payer)]), 200,
          headers: {'content-type': 'application/json; charset=utf-8'})),
    ));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActiveScreen(api: api, onCount: (_) {}, onChanged: () {}))));
    await tester.pumpAndSettle();
    expect(find.textContaining('9,25 da loja ao retirar'), findsOneWidget);
    status = 'PICKED_UP';
    payer = 'CUSTOMER';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActiveScreen(key: UniqueKey(), api: api, onCount: (_) {}, onChanged: () {}))));
    await tester.pumpAndSettle();
    expect(find.textContaining('do cliente na entrega (dinheiro ou Pix)'), findsOneWidget);
  });

  testWidgets('mural: mostra o total com bônus e o selo do bônus', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _api({'GET /api/courier/jobs/open': (200, _page([_card(5, bonus: 3)]))}, []);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BoardScreen(api: api, profile: _profile(), onProfile: (_) {}, onAccepted: () {}, locate: () async => null, visible: false),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('12,25'), findsOneWidget); // 9,25 de frete + 3,00 de bônus
    expect(find.textContaining('Bônus +'), findsOneWidget);
    expect(find.textContaining('pago pela loja na coleta'), findsOneWidget);
  });

  testWidgets('em andamento: envia a posição enquanto há corrida ativa, lembra o bônus e mostra o aviso', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    final api = CourierApi(ApiClient(
      baseUrl: 'http://api.test',
      httpClient: MockClient((req) async {
        if (req.method == 'POST') sent.add('${req.url.path} ${req.body}');
        return http.Response(req.method == 'POST' ? '' : jsonEncode([_job(bonus: 3, payer: 'STORE')]), req.method == 'POST' ? 204 : 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    ));
    final reporter = LocationReporter(send: api.sendLocation, locate: () async => const GeoPoint(-22.9, -47.06), every: const Duration(seconds: 15));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActiveScreen(api: api, reporter: reporter, onCount: (_) {}, onChanged: () {}))));
    await tester.pumpAndSettle();
    expect(reporter.running, isTrue);
    expect(sent.first, '/api/courier/jobs/5/location {"lat":-22.9,"lng":-47.06}');
    expect(find.textContaining('Compartilhando sua posição'), findsOneWidget);
    expect(find.textContaining('Deixe o app aberto'), findsOneWidget);
    expect(find.textContaining('Receba o bônus de'), findsOneWidget);
    expect(find.textContaining('12,25'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // sai da tela: para o envio
    expect(reporter.running, isFalse);
  });

  test('LocationReporter: manda a posição, para quando a corrida acaba (422) e ignora falha de rede', () async {
    final calls = <String>[];
    var mode = 'ok';
    final r = LocationReporter(
      send: (id, lat, lng) async {
        calls.add('$id');
        if (mode == 'end') throw ApiException(422, 'Esta corrida já acabou');
        if (mode == 'net') throw Exception('sem rede');
      },
      locate: () async => const GeoPoint(1, 2),
      every: const Duration(hours: 1),
    );
    r.update([5], foreground: false);
    expect(r.running, isFalse); // em segundo plano não envia
    r.update([5], foreground: true);
    await Future<void>.delayed(Duration.zero); // a primeira posição sai já ao ligar
    expect(calls, ['5']);
    await r.tick();
    expect(calls, ['5', '5']);
    mode = 'net';
    await r.tick();
    expect(r.jobs, {5}); // falha de rede: segue tentando
    mode = 'end';
    await r.tick();
    expect(r.jobs, isEmpty);
    expect(r.running, isFalse);
    r.update([], foreground: true);
    expect(r.running, isFalse);
  });

  testWidgets('conta: mostra a média de avaliações e o CPF mascarado', (tester) async {
    final api = _api({
      'GET /api/courier/subscription': (200, {'subscribed': false, 'paidUntil': null, 'freeLeft': 3, 'freeLimit': 5, 'price': 24.99, 'canAccept': true}),
    }, []);
    const p = CourierProfile(
        id: 1, name: 'Zé Moto', email: 'ze@x.com', phone: '11988887777', vehicle: 'MOTO', city: 'Campinas', state: 'SP',
        radiusKm: 10, status: 'APPROVED', online: true, deliveredCount: 23, canceledCount: 0, cpfMasked: '***.982.247-**',
        ratingAvg: 4.8, ratingCount: 23);
    await tester.pumpWidget(AppScope(
      session: Session(),
      child: MaterialApp(home: Scaffold(body: AccountTab(api: api, profile: p, onProfile: (_) {}))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('★ 4,8 (23 avaliações)'), findsOneWidget);
    expect(find.textContaining('***.982.247-**'), findsOneWidget);
    expect(ratingText(null, 0), 'Sem avaliações ainda');
    expect(ratingText(5, 1), '★ 5,0 (1 avaliação)');
  });

  test('CPF: dígitos verificadores e máscara', () {
    expect(cpfValid('529.982.247-25'), isTrue);
    expect(cpfValid('52998224725'), isTrue);
    expect(cpfValid('529.982.247-24'), isFalse);
    expect(cpfValid('111.111.111-11'), isFalse);
    expect(cpfValid('123'), isFalse);
    expect(CpfFormatter().formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '52998224725999')).text, '529.982.247-25');
  });

  test('tempo até expirar', () {
    final now = DateTime(2026, 10, 27, 10);
    expect(expiresIn(now.add(const Duration(minutes: 23, seconds: 30)), now: now), 'expira em 23 min');
    expect(expiresIn(now.add(const Duration(seconds: 20)), now: now), 'expira em instantes');
    expect(expiresIn(now.add(const Duration(hours: 2)), now: now), 'expira em 2 h');
  });
}
