// ignore_for_file: invalid_use_of_visible_for_testing_member
// Gera as imagens das telas principais com dados de exemplo (para apresentar o app e revisar o visual).
//
//   flutter test screenshots/telas_test.dart
//
// Salva em ../docs/telas/*.png. A API é simulada; as "fotos" dos produtos são as ilustrações de screenshots/fotos.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:loja_max/api_client.dart';
import 'package:loja_max/app_scope.dart';
import 'package:loja_max/cart.dart';
import 'package:loja_max/current_store.dart';
import 'package:loja_max/models.dart';
import 'package:loja_max/screens/cart_screen.dart';
import 'package:loja_max/screens/customer_shell.dart';
import 'package:loja_max/screens/login_screen.dart';
import 'package:loja_max/screens/order_screen.dart';
import 'package:loja_max/screens/product_screen.dart';
import 'package:loja_max/screens/store_picker_screen.dart';
import 'package:loja_max/session.dart';
import 'package:loja_max/store/product_form_screen.dart';
import 'package:loja_max/store/report_screen.dart';
import 'package:loja_max/store/store_orders_screen.dart';
import 'package:loja_max/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _api = 'http://api.test';
final _out = Directory('../docs/telas');

String _photo(String name) => '$_api/fotos/$name.jpg';

Map<String, dynamic> _card(int id, String name, String dept, String foto, double price,
        {double? finalPrice, int discount = 0, int stock = 8, bool featured = false}) =>
    {
      'id': id,
      'name': name,
      'department': dept,
      'brand': null,
      'price': price,
      'finalPrice': finalPrice ?? price,
      'discountPercent': discount,
      'thumbUrl': _photo(foto),
      'inStock': stock > 0,
      'featured': featured,
      'totalStock': stock,
      'active': true,
    };

final _cards = [
  _card(1, 'Vestido Midi Floral', 'ROUPAS', 'vestido', 189.9, finalPrice: 132.93, discount: 30, featured: true),
  _card(2, 'Tênis Runner Leve', 'CALCADOS', 'tenis', 249.9, finalPrice: 199.92, discount: 20),
  _card(3, 'Brinco Argola Dourada', 'BIJUTERIAS', 'brinco', 39.9),
  _card(4, 'Jaqueta Jeans Oversized', 'ROUPAS', 'jaqueta', 229.9),
  _card(5, 'Bota Cano Curto Couro', 'CALCADOS', 'bota', 319.9, stock: 0),
  _card(6, 'Relógio Minimalista', 'BIJUTERIAS', 'relogio', 159.9, finalPrice: 127.92, discount: 20),
  _card(7, 'Bolsa Tiracolo Caramelo', 'BIJUTERIAS', 'bolsa', 179.9),
  _card(8, 'Patins Retrô', 'CALCADOS', 'patins', 399.9),
];

Map<String, dynamic> _page(List<Object> items) =>
    {'items': items, 'page': 0, 'size': 20, 'total': items.length, 'hasMore': false};

final _product = {
  'id': 1,
  'name': 'Vestido Midi Floral',
  'description': 'Viscose leve com estampa floral, alças finas reguláveis e fenda lateral. Forro até a coxa.\n'
      'Modelo veste P · Lavar à mão.',
  'department': 'ROUPAS',
  'categoryId': 10,
  'categoryName': 'Vestidos',
  'brand': 'Ateliê Max',
  'price': 189.9,
  'salePrice': null,
  'finalPrice': 132.93,
  'discountPercent': 30,
  'promotion': 'Semana da Primavera',
  'minStock': 1,
  'active': true,
  'featured': true,
  'totalStock': 6,
  'variants': [
    {'id': 11, 'size': 'P', 'color': 'Rosa', 'sku': null, 'stock': 2, 'active': true},
    {'id': 12, 'size': 'M', 'color': 'Rosa', 'sku': null, 'stock': 4, 'active': true},
    {'id': 13, 'size': 'G', 'color': 'Rosa', 'sku': null, 'stock': 0, 'active': true},
  ],
  'photos': [
    {'id': 1, 'url': _photo('vestido'), 'thumbUrl': _photo('vestido'), 'width': 640, 'height': 640, 'position': 0},
    {'id': 2, 'url': _photo('bolsa'), 'thumbUrl': _photo('bolsa'), 'width': 640, 'height': 640, 'position': 1},
  ],
  'createdAt': '2026-10-20T10:00:00',
};

Map<String, dynamic> _order({bool team = false}) => {
      'id': 42,
      'code': 'K7Q2MD',
      'status': 'READY',
      'nextStatuses': team ? ['DELIVERED', 'CANCELED'] : [],
      'canCancel': false,
      'deliveryMethod': 'PICKUP',
      'paymentMethod': 'PIX',
      'paid': true,
      'address': null,
      'notes': 'Embalar para presente, por favor.',
      'subtotal': 332.85,
      'discount': 96.93,
      'deliveryFee': 0,
      'total': 332.85,
      'cancelReason': null,
      'createdAt': '2026-10-27T09:12:00',
      'updatedAt': '2026-10-27T11:40:00',
      'customer': team ? {'id': 5, 'name': 'Ana Souza', 'email': 'ana@email.com', 'phone': '(11) 98888-1234'} : null,
      'items': [
        {'productId': 1, 'variantId': 12, 'productName': 'Vestido Midi Floral', 'size': 'M', 'color': 'Rosa', 'unitPrice': 132.93, 'quantity': 1, 'total': 132.93, 'thumbUrl': _photo('vestido')},
        {'productId': 2, 'variantId': 21, 'productName': 'Tênis Runner Leve', 'size': '37', 'color': 'Branco', 'unitPrice': 199.92, 'quantity': 1, 'total': 199.92, 'thumbUrl': _photo('tenis')},
      ],
      'events': [
        {'status': 'PENDING', 'label': '', 'note': null, 'byCustomer': true, 'createdAt': '2026-10-27T09:12:00'},
        {'status': 'CONFIRMED', 'label': '', 'note': null, 'byCustomer': false, 'createdAt': '2026-10-27T09:30:00'},
        {'status': 'READY', 'label': '', 'note': 'Separado no balcão 2', 'byCustomer': false, 'createdAt': '2026-10-27T11:40:00'},
      ],
    };

Map<String, dynamic> _summary(int id, String code, String status, String name, String foto, double total, int items,
        {bool delivery = false, bool paid = false, int minutesAgo = 10}) =>
    {
      'id': id,
      'code': code,
      'status': status,
      'statusLabel': '',
      'deliveryMethod': delivery ? 'DELIVERY' : 'PICKUP',
      'paid': paid,
      'total': total,
      'itemCount': items,
      'customerName': name,
      'firstItem': '',
      'thumbUrl': _photo(foto),
      'createdAt': DateTime.now().subtract(Duration(minutes: minutesAgo)).toIso8601String().substring(0, 19),
    };

Object? _route(String path) {
  if (path == '/api/public/stores') {
    return _page([
      {'id': 1, 'slug': 'moda-da-ana', 'name': 'Moda da Ana', 'instagram': 'modadaana'},
      {'id': 2, 'slug': 'pe-direito', 'name': 'Pé Direito Calçados', 'instagram': 'pedireito'},
      {'id': 3, 'slug': 'brilho-bijus', 'name': 'Brilho Bijus', 'instagram': 'brilhobijus'},
      {'id': 4, 'slug': 'casa-da-moda', 'name': 'Casa da Moda', 'instagram': null},
    ]);
  }
  if (path == '/api/public/stores/moda-da-ana') {
    return {
      'id': 1, 'slug': 'moda-da-ana', 'name': 'Moda da Ana', 'whatsapp': '11999990000', 'instagram': 'modadaana',
      'pickupAddress': 'Rua das Flores, 120 - Centro', 'pickupEnabled': true, 'deliveryEnabled': true,
      'deliveryFee': 12, 'freeDeliveryFrom': 250,
    };
  }
  if (path.endsWith('/categories')) {
    return [
      {'id': 10, 'department': 'ROUPAS', 'name': 'Vestidos', 'position': 0, 'active': true},
      {'id': 11, 'department': 'ROUPAS', 'name': 'Jaquetas', 'position': 1, 'active': true},
    ];
  }
  if (path.endsWith('/promotions')) {
    final now = DateTime.now();
    return [
      {'id': 1, 'title': 'Semana da Primavera', 'description': null, 'discountPercent': 30, 'department': 'ROUPAS',
        'categoryId': null, 'productId': null, 'scope': 'Roupas', 'startsAt': now.toIso8601String().substring(0, 19),
        'endsAt': now.add(const Duration(days: 5)).toIso8601String().substring(0, 19), 'active': true, 'running': true,
        'notifyCustomers': true},
      {'id': 2, 'title': 'Tênis em dobro', 'description': null, 'discountPercent': 20, 'department': 'CALCADOS',
        'categoryId': null, 'productId': null, 'scope': 'Calçados', 'startsAt': now.toIso8601String().substring(0, 19),
        'endsAt': now.add(const Duration(days: 5)).toIso8601String().substring(0, 19), 'active': true, 'running': true,
        'notifyCustomers': true},
    ];
  }
  if (path == '/api/public/stores/moda-da-ana/products') return _page(_cards);
  if (path == '/api/public/stores/moda-da-ana/products/1' || path == '/api/store/products/1') return _product;
  if (path == '/api/stores/moda-da-ana/orders/42') return _order();
  if (path == '/api/store/orders/42') return _order(team: true);
  if (path == '/api/store/orders') {
    return _page([
      _summary(45, 'R8T2KC', 'PENDING', 'Beatriz Lima', 'bota', 319.90, 1, delivery: true, minutesAgo: 3),
      _summary(44, 'P3MX9A', 'PENDING', 'Carla Mendes', 'brinco', 79.80, 2, minutesAgo: 25),
      _summary(43, 'Z6WQ4E', 'CONFIRMED', 'Daniel Rocha', 'jaqueta', 229.90, 1, delivery: true, paid: true, minutesAgo: 70),
      _summary(42, 'K7Q2MD', 'READY', 'Ana Souza', 'vestido', 332.85, 2, paid: true, minutesAgo: 150),
      _summary(41, 'H2NB7S', 'SHIPPED', 'Eduarda Alves', 'tenis', 199.92, 1, delivery: true, paid: true, minutesAgo: 300),
    ]);
  }
  if (path == '/api/store/categories') return _route('/categories');
  if (path == '/api/store/variants/11/stock') return _page([]);
  if (path == '/api/store/reports/summary') {
    final today = DateTime.now();
    final days = [
      for (var i = 20; i >= 0; i--)
        {
          'date': today.subtract(Duration(days: i)).toIso8601String().substring(0, 10),
          'orders': 3 + (i * 7 % 6),
          'revenue': 420 + (i * 137 % 900) + (i % 7 == 5 ? 900 : 0),
        },
    ];
    return {
      'from': days.first['date'], 'to': days.last['date'], 'orders': 96, 'revenue': 18420.5, 'paidRevenue': 16210.3,
      'averageTicket': 191.88, 'itemsSold': 154, 'discounts': 2310.4, 'newCustomers': 37,
      'byStatus': {'DELIVERED': 71, 'READY': 6, 'SHIPPED': 9, 'CONFIRMED': 5, 'PENDING': 5, 'CANCELED': 4},
      'topProducts': [
        {'productId': 1, 'name': 'Vestido Midi Floral', 'quantity': 31, 'revenue': 4120.83},
        {'productId': 2, 'name': 'Tênis Runner Leve', 'quantity': 22, 'revenue': 4398.24},
        {'productId': 3, 'name': 'Brinco Argola Dourada', 'quantity': 19, 'revenue': 758.1},
      ],
      'days': days, 'pendingNow': 5,
      'lowStock': [
        {'productId': 5, 'productName': 'Bota Cano Curto Couro', 'variantId': 51, 'variant': '37 · Preto', 'stock': 0, 'minStock': 1},
        {'productId': 1, 'productName': 'Vestido Midi Floral', 'variantId': 11, 'variant': 'P · Rosa', 'stock': 1, 'minStock': 1},
      ],
    };
  }
  return null;
}

final _client = MockClient((req) async {
  final body = _route(req.url.path);
  return http.Response(jsonEncode(body ?? {'detail': 'Não encontrado.'}), body == null ? 404 : 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
});

/// Imagens: o Image.network usa o HttpClient do dart:io; aqui ele devolve as ilustrações locais.
class _Images extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient();
}

class _FakeClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.url);

  final Uri url;

  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async {
    final file = File('screenshots/fotos/${url.pathSegments.last}');
    return _FakeResponse(file.existsSync() ? file.readAsBytesSync() : <int>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.bytes);

  final List<int> bytes;

  @override
  int get statusCode => bytes.isEmpty ? 404 : 200;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(bytes).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(read(f));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

final _boundary = GlobalKey();

Widget _frame(Widget home, {Session? session, Cart? cart, CurrentStore? store, bool dark = false}) => AppScope(
      session: session ?? Session(httpClient: _client),
      cart: cart ?? Cart(),
      store: store ?? CurrentStore(),
      child: RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: home,
        ),
      ),
    );

/// Deixa as requisições e as fotos terminarem (são assíncronas de verdade) e salva o PNG.
Future<void> _shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 300));
  }
  final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!;
  });
  _out.createSync(recursive: true);
  File('${_out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = _Images();
    await initializeDateFormatting('pt_BR');
    await _loadFonts();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  final api = ApiClient(baseUrl: _api, httpClient: _client);

  testWidgets('01 escolher loja', (tester) async {
    await phone(tester);
    final store = CurrentStore();
    await tester.pumpWidget(_frame(StorePickerScreen(api: api), store: store));
    await _shot(tester, '01-escolher-loja');
  });

  testWidgets('02 vitrine', (tester) async {
    await phone(tester);
    final store = CurrentStore()..open(const StoreCard(slug: 'moda-da-ana', name: 'Moda da Ana'));
    final cart = Cart()
      ..add(CartItem(variantId: 12, productId: 1, name: 'Vestido', variant: 'M', unitPrice: 132.93, quantity: 2, maxStock: 4),
          store: 'moda-da-ana');
    await tester.pumpWidget(_frame(const CustomerShell(), store: store, cart: cart, session: Session(httpClient: _client)));
    await _shot(tester, '02-vitrine');
  });

  testWidgets('03 produto', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_frame(ProductScreen(api: api, slug: 'moda-da-ana', productId: 1)));
    await _shot(tester, '03-produto');
  });

  testWidgets('04 carrinho', (tester) async {
    await phone(tester);
    final cart = Cart()
      ..add(CartItem(variantId: 12, productId: 1, name: 'Vestido Midi Floral', variant: 'M · Rosa', unitPrice: 132.93,
          quantity: 1, maxStock: 4, thumbUrl: _photo('vestido')), store: 'moda-da-ana')
      ..add(CartItem(variantId: 21, productId: 2, name: 'Tênis Runner Leve', variant: '37 · Branco', unitPrice: 199.92,
          quantity: 1, maxStock: 3, thumbUrl: _photo('tenis')), store: 'moda-da-ana')
      ..add(CartItem(variantId: 31, productId: 3, name: 'Brinco Argola Dourada', variant: 'Único · Dourado', unitPrice: 39.9,
          quantity: 2, maxStock: 9, thumbUrl: _photo('brinco')), store: 'moda-da-ana');
    await tester.pumpWidget(_frame(const CartScreen(), cart: cart));
    await _shot(tester, '04-carrinho');
  });

  testWidgets('05 pedido do cliente', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_frame(OrderScreen(api: api, orderId: 42, slug: 'moda-da-ana')));
    await _shot(tester, '05-pedido-cliente');
  });

  testWidgets('06 entrar', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_frame(const LoginScreen()));
    await _shot(tester, '06-entrar');
  });

  testWidgets('07 gestão: pedidos', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_frame(StoreOrdersScreen(api: api)));
    await _shot(tester, '07-gestao-pedidos');
  });

  testWidgets('08 gestão: pedido', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_frame(OrderScreen(api: api, orderId: 42, team: true)));
    await _shot(tester, '08-gestao-pedido');
  });

  testWidgets('09 gestão: produto', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_frame(ProductFormScreen(api: api, productId: 1)));
    await _shot(tester, '09-gestao-produto');
  });

  testWidgets('10 gestão: resumo de vendas', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_frame(ReportScreen(api: api)));
    await _shot(tester, '10-resumo-vendas');
  });

  testWidgets('11 vitrine no modo escuro', (tester) async {
    await phone(tester);
    final store = CurrentStore()..open(const StoreCard(slug: 'moda-da-ana', name: 'Moda da Ana'));
    await tester.pumpWidget(_frame(const CustomerShell(), store: store, dark: true));
    await _shot(tester, '11-vitrine-escuro');
  });
}
