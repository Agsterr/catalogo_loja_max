// Modelos das respostas da API (mesmos nomes de campo dos DTOs do Spring).

double _d(Object? v) => v == null ? 0 : (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
DateTime _dt(Object? v) => DateTime.parse(v as String);
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

enum Role { owner, staff, customer, platformAdmin }

Role _role(String v) => switch (v) {
      'OWNER' => Role.owner,
      'STAFF' => Role.staff,
      'PLATFORM_ADMIN' => Role.platformAdmin,
      _ => Role.customer,
    };

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    this.storeSlug,
    this.storeName,
    this.twoFactorEnabled = false,
    this.blocked = false,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final Role role;

  /// Loja da equipe (nulo para cliente e admin da plataforma).
  final String? storeSlug;
  final String? storeName;
  final bool twoFactorEnabled;
  final bool blocked;

  bool get isTeam => role == Role.owner || role == Role.staff;
  bool get isOwner => role == Role.owner;
  bool get isPlatformAdmin => role == Role.platformAdmin;

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String?,
        role: _role(j['role'] as String),
        storeSlug: j['storeSlug'] as String?,
        storeName: j['storeName'] as String?,
        twoFactorEnabled: j['twoFactorEnabled'] as bool? ?? false,
        blocked: j['blocked'] as bool? ?? false,
      );
}

/// Loja na busca do app do cliente.
class StoreCard {
  const StoreCard({required this.slug, required this.name, this.instagram, this.description, this.logoUrl, this.status, this.city, this.state, this.distanceKm});

  final String slug;
  final String name;
  final String? instagram;
  final String? description;
  final String? logoUrl;
  final OpenStatus? status;
  final String? city;
  final String? state;

  /// Só quando a busca mandou a posição do cliente e a loja informou a dela.
  final double? distanceKm;

  /// "Cidade - UF" (ou só a cidade).
  String? get place => city == null ? null : (state == null ? city : '$city - $state');

  Map<String, dynamic> toJson() =>
      {'slug': slug, 'name': name, 'instagram': instagram, 'description': description, 'logoUrl': logoUrl};

  factory StoreCard.fromJson(Map<String, dynamic> j) => StoreCard(
        slug: j['slug'] as String,
        name: j['name'] as String,
        instagram: j['instagram'] as String?,
        description: j['description'] as String?,
        logoUrl: j['logoUrl'] as String?,
        status: OpenStatus.from(j['status']),
        city: j['city'] as String?,
        state: j['state'] as String?,
        distanceKm: _dn(j['distanceKm']),
      );
}

/// Faixa de entrega: até [upToKm] km custa [fee].
class DeliveryZone {
  const DeliveryZone(this.upToKm, this.fee);

  final double upToKm;
  final double fee;

  Map<String, dynamic> toJson() => {'upToKm': upToKm, 'fee': fee};

  factory DeliveryZone.fromJson(Map<String, dynamic> j) => DeliveryZone(_d(j['upToKm']), _d(j['fee']));
}

/// Taxa de entrega para a posição do cliente (loja que cobra por distância).
class DeliveryQuote {
  const DeliveryQuote({required this.available, required this.needsLocation, this.distanceKm, this.fee, this.message});

  final bool available;
  final bool needsLocation;
  final double? distanceKm;
  final double? fee;
  final String? message;

  factory DeliveryQuote.fromJson(Map<String, dynamic> j) => DeliveryQuote(
        available: j['available'] as bool,
        needsLocation: j['needsLocation'] as bool,
        distanceKm: _dn(j['distanceKm']),
        fee: _dn(j['fee']),
        message: j['message'] as String?,
      );
}

/// Cidade que tem loja, com a quantidade (filtro do cliente).
class CityCount {
  const CityCount({required this.city, this.state, required this.total});

  final String city;
  final String? state;
  final int total;

  factory CityCount.fromJson(Map<String, dynamic> j) =>
      CityCount(city: j['city'] as String, state: j['state'] as String?, total: (j['total'] as num).toInt());
}

/// Seções da loja.
enum Department {
  roupas('ROUPAS', 'Roupas'),
  calcados('CALCADOS', 'Calçados'),
  bijuterias('BIJUTERIAS', 'Bijuterias');

  const Department(this.api, this.label);

  final String api;
  final String label;

  static Department of(String v) => values.firstWhere((d) => d.api == v);
}

class PageResult<T> {
  const PageResult(this.items, this.page, this.hasMore, this.total);

  final List<T> items;
  final int page;
  final bool hasMore;
  final int total;

  factory PageResult.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) f) =>
      PageResult(_list(j['items'], f), j['page'] as int, j['hasMore'] as bool, (j['total'] as num).toInt());
}

class Category {
  const Category({required this.id, required this.department, required this.name, required this.position, required this.active});

  final int id;
  final Department department;
  final String name;
  final int position;
  final bool active;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as int,
        department: Department.of(j['department'] as String),
        name: j['name'] as String,
        position: j['position'] as int,
        active: j['active'] as bool,
      );
}

class Photo {
  const Photo({required this.id, required this.url, required this.thumbUrl, required this.width, required this.height, this.color});

  final int id;

  /// Cor da peça na foto (nulo = vale para todas).
  final String? color;
  final String url;
  final String thumbUrl;
  final int width;
  final int height;

  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
        id: j['id'] as int,
        url: j['url'] as String,
        thumbUrl: j['thumbUrl'] as String,
        width: j['width'] as int,
        height: j['height'] as int,
        color: j['color'] as String?,
      );
}

class Variant {
  const Variant({required this.id, required this.size, required this.color, this.sku, required this.stock, required this.active});

  final int id;
  final String size;
  final String color;
  final String? sku;
  final int stock;
  final bool active;

  String get label => color.isEmpty ? size : '$size · $color';

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
        id: j['id'] as int,
        size: j['size'] as String,
        color: j['color'] as String? ?? '',
        sku: j['sku'] as String?,
        stock: j['stock'] as int,
        active: j['active'] as bool,
      );
}

/// Cartão da vitrine.
class ProductCard {
  const ProductCard({
    required this.id,
    required this.name,
    required this.department,
    this.brand,
    required this.price,
    required this.finalPrice,
    required this.discountPercent,
    this.thumbUrl,
    required this.inStock,
    required this.featured,
    required this.totalStock,
    required this.active,
  });

  final int id;
  final String name;
  final Department department;
  final String? brand;
  final double price;
  final double finalPrice;
  final int discountPercent;
  final String? thumbUrl;
  final bool inStock;
  final bool featured;
  final int totalStock;
  final bool active;

  bool get onSale => finalPrice < price;

  factory ProductCard.fromJson(Map<String, dynamic> j) => ProductCard(
        id: j['id'] as int,
        name: j['name'] as String,
        department: Department.of(j['department'] as String),
        brand: j['brand'] as String?,
        price: _d(j['price']),
        finalPrice: _d(j['finalPrice']),
        discountPercent: j['discountPercent'] as int,
        thumbUrl: j['thumbUrl'] as String?,
        inStock: j['inStock'] as bool,
        featured: j['featured'] as bool,
        totalStock: j['totalStock'] as int,
        active: j['active'] as bool,
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    this.description,
    this.sizeChart,
    required this.department,
    this.categoryId,
    this.categoryName,
    this.brand,
    required this.price,
    this.salePrice,
    required this.finalPrice,
    required this.discountPercent,
    this.promotion,
    required this.minStock,
    required this.active,
    required this.featured,
    required this.totalStock,
    required this.variants,
    required this.photos,
  });

  final int id;
  final String name;
  final String? description;

  /// Tabela de medidas (texto livre).
  final String? sizeChart;
  final Department department;
  final int? categoryId;
  final String? categoryName;
  final String? brand;
  final double price;
  final double? salePrice;
  final double finalPrice;
  final int discountPercent;
  final String? promotion;
  final int minStock;
  final bool active;
  final bool featured;
  final int totalStock;
  final List<Variant> variants;
  final List<Photo> photos;

  bool get onSale => finalPrice < price;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String?,
        sizeChart: j['sizeChart'] as String?,
        department: Department.of(j['department'] as String),
        categoryId: j['categoryId'] as int?,
        categoryName: j['categoryName'] as String?,
        brand: j['brand'] as String?,
        price: _d(j['price']),
        salePrice: _dn(j['salePrice']),
        finalPrice: _d(j['finalPrice']),
        discountPercent: j['discountPercent'] as int,
        promotion: j['promotion'] as String?,
        minStock: j['minStock'] as int,
        active: j['active'] as bool,
        featured: j['featured'] as bool,
        totalStock: j['totalStock'] as int,
        variants: _list(j['variants'], Variant.fromJson),
        photos: _list(j['photos'], Photo.fromJson),
      );
}

/// Aberta/fechada agora ("Aberta agora · fecha às 18:00").
class OpenStatus {
  const OpenStatus({required this.open, required this.label});

  final bool open;
  final String label;

  static OpenStatus? from(Object? j) =>
      j == null ? null : OpenStatus(open: (j as Map<String, dynamic>)['open'] as bool, label: j['label'] as String);
}

/// Horário de um dia (vazio = fechado), "HH:mm".
class DayHours {
  const DayHours(this.open, this.close);

  final String open;
  final String close;

  bool get closed => open.isEmpty || close.isEmpty;

  Map<String, dynamic> toJson() => {'open': open, 'close': close};
}

class StoreInfo {
  const StoreInfo({
    required this.slug,
    required this.name,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.openingHours,
    this.hours = const [],
    this.status,
    this.whatsapp,
    this.instagram,
    this.pickupAddress,
    required this.pickupEnabled,
    required this.deliveryEnabled,
    required this.deliveryFee,
    this.freeDeliveryFrom,
    this.city,
    this.state,
    this.latitude,
    this.longitude,
    this.deliveryZones = const [],
  });

  final String slug;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverUrl;

  /// Os 7 dias (segunda a domingo) quando a loja informou; [hours] são as linhas prontas para mostrar.
  final List<DayHours>? openingHours;
  final List<String> hours;
  final OpenStatus? status;
  final String? whatsapp;
  final String? instagram;
  final String? pickupAddress;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final double deliveryFee;
  final double? freeDeliveryFrom;
  final String? city;
  final String? state;
  final double? latitude;
  final double? longitude;

  /// Entrega por distância (vazio = taxa fixa).
  final List<DeliveryZone> deliveryZones;

  factory StoreInfo.fromJson(Map<String, dynamic> j) => StoreInfo(
        slug: j['slug'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        logoUrl: j['logoUrl'] as String?,
        coverUrl: j['coverUrl'] as String?,
        openingHours: (j['openingHours'] as List?)
            ?.map((d) => DayHours((d as Map<String, dynamic>)['open'] as String? ?? '', d['close'] as String? ?? ''))
            .toList(),
        hours: (j['hours'] as List? ?? const []).cast<String>(),
        status: OpenStatus.from(j['status']),
        whatsapp: j['whatsapp'] as String?,
        instagram: j['instagram'] as String?,
        pickupAddress: j['pickupAddress'] as String?,
        pickupEnabled: j['pickupEnabled'] as bool,
        deliveryEnabled: j['deliveryEnabled'] as bool,
        deliveryFee: _d(j['deliveryFee']),
        freeDeliveryFrom: _dn(j['freeDeliveryFrom']),
        city: j['city'] as String?,
        state: j['state'] as String?,
        latitude: _dn(j['latitude']),
        longitude: _dn(j['longitude']),
        deliveryZones: (j['deliveryZones'] as List? ?? const [])
            .map((z) => DeliveryZone.fromJson(z as Map<String, dynamic>))
            .toList(),
      );
}

enum OrderStatus {
  pending('PENDING', 'Aguardando confirmação'),
  confirmed('CONFIRMED', 'Confirmado'),
  ready('READY', 'Pronto para retirar'),
  shipped('SHIPPED', 'Saiu para entrega'),
  delivered('DELIVERED', 'Entregue'),
  canceled('CANCELED', 'Cancelado');

  const OrderStatus(this.api, this.label);

  final String api;
  final String label;

  bool get finished => this == delivered || this == canceled;

  static OrderStatus of(String v) => values.firstWhere((s) => s.api == v);
}

const paymentLabels = {'PIX': 'Pix', 'CARD': 'Cartão', 'CASH': 'Dinheiro'};

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.code,
    required this.status,
    required this.delivery,
    required this.paid,
    required this.total,
    required this.itemCount,
    required this.customerName,
    this.firstItem,
    this.thumbUrl,
    required this.createdAt,
  });

  final int id;
  final String code;
  final OrderStatus status;
  final bool delivery;
  final bool paid;
  final double total;
  final int itemCount;
  final String customerName;
  final String? firstItem;
  final String? thumbUrl;
  final DateTime createdAt;

  factory OrderSummary.fromJson(Map<String, dynamic> j) => OrderSummary(
        id: j['id'] as int,
        code: j['code'] as String,
        status: OrderStatus.of(j['status'] as String),
        delivery: j['deliveryMethod'] == 'DELIVERY',
        paid: j['paid'] as bool,
        total: _d(j['total']),
        itemCount: j['itemCount'] as int,
        customerName: j['customerName'] as String,
        firstItem: j['firstItem'] as String?,
        thumbUrl: j['thumbUrl'] as String?,
        createdAt: _dt(j['createdAt']),
      );
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.productName,
    required this.size,
    required this.color,
    required this.unitPrice,
    required this.quantity,
    required this.total,
    this.thumbUrl,
  });

  final int productId;
  final String productName;
  final String size;
  final String color;
  final double unitPrice;
  final int quantity;
  final double total;
  final String? thumbUrl;

  String get variant => color.isEmpty ? size : '$size · $color';

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        productId: j['productId'] as int,
        productName: j['productName'] as String,
        size: j['size'] as String,
        color: j['color'] as String? ?? '',
        unitPrice: _d(j['unitPrice']),
        quantity: j['quantity'] as int,
        total: _d(j['total']),
        thumbUrl: j['thumbUrl'] as String?,
      );
}

class OrderEvent {
  const OrderEvent({required this.status, this.note, required this.byCustomer, required this.createdAt});

  final OrderStatus status;
  final String? note;
  final bool byCustomer;
  final DateTime createdAt;

  factory OrderEvent.fromJson(Map<String, dynamic> j) => OrderEvent(
        status: OrderStatus.of(j['status'] as String),
        note: j['note'] as String?,
        byCustomer: j['byCustomer'] as bool,
        createdAt: _dt(j['createdAt']),
      );
}

class Customer {
  const Customer({required this.id, required this.name, required this.email, this.phone});

  final int id;
  final String name;
  final String email;
  final String? phone;

  factory Customer.fromJson(Map<String, dynamic> j) =>
      Customer(id: j['id'] as int, name: j['name'] as String, email: j['email'] as String, phone: j['phone'] as String?);
}

class Order {
  const Order({
    required this.id,
    required this.code,
    required this.status,
    required this.nextStatuses,
    required this.canCancel,
    required this.delivery,
    required this.paymentMethod,
    required this.paid,
    this.address,
    this.notes,
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.total,
    this.cancelReason,
    required this.createdAt,
    this.customer,
    required this.items,
    required this.events,
    this.storeSlug,
  });

  final int id;
  final String code;
  final OrderStatus status;
  final List<OrderStatus> nextStatuses;
  final bool canCancel;
  final bool delivery;
  final String paymentMethod;
  final bool paid;
  final String? address;
  final String? notes;
  final double subtotal;
  final double discount;
  final double deliveryFee;
  final double total;
  final String? cancelReason;
  final DateTime createdAt;

  /// Só nas respostas da gestão.
  final Customer? customer;
  final List<OrderItem> items;
  final List<OrderEvent> events;

  /// Loja do pedido (o app sabe por onde comprou).
  final String? storeSlug;

  factory Order.fromJson(Map<String, dynamic> j, {String? storeSlug}) => Order(
        storeSlug: storeSlug,
        id: j['id'] as int,
        code: j['code'] as String,
        status: OrderStatus.of(j['status'] as String),
        nextStatuses: (j['nextStatuses'] as List? ?? const []).map((s) => OrderStatus.of(s as String)).toList(),
        canCancel: j['canCancel'] as bool,
        delivery: j['deliveryMethod'] == 'DELIVERY',
        paymentMethod: j['paymentMethod'] as String,
        paid: j['paid'] as bool,
        address: j['address'] as String?,
        notes: j['notes'] as String?,
        subtotal: _d(j['subtotal']),
        discount: _d(j['discount']),
        deliveryFee: _d(j['deliveryFee']),
        total: _d(j['total']),
        cancelReason: j['cancelReason'] as String?,
        createdAt: _dt(j['createdAt']),
        customer: j['customer'] == null ? null : Customer.fromJson(j['customer'] as Map<String, dynamic>),
        items: _list(j['items'], OrderItem.fromJson),
        events: _list(j['events'], OrderEvent.fromJson),
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    this.orderId,
    this.productId,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.read,
    this.storeSlug,
    this.storeName,
  });

  final int id;
  final String type;
  final int? orderId;
  final int? productId;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool read;

  /// Loja do aviso (o cliente recebe de todas em que comprou).
  final String? storeSlug;
  final String? storeName;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        type: j['type'] as String,
        orderId: j['orderId'] as int?,
        productId: j['productId'] as int?,
        title: j['title'] as String,
        message: j['message'] as String,
        createdAt: _dt(j['createdAt']),
        read: j['read'] as bool,
        storeSlug: j['storeSlug'] as String?,
        storeName: j['storeName'] as String?,
      );
}

/// Uma página do sino; [unread] conta todos os não lidos.
class Inbox {
  const Inbox(this.unread, this.items, {this.hasMore = false});

  final int unread;
  final List<AppNotification> items;
  final bool hasMore;

  factory Inbox.fromJson(Map<String, dynamic> j) => Inbox(
        (j['unread'] as num).toInt(),
        _list(j['items'], AppNotification.fromJson),
        hasMore: j['hasMore'] as bool? ?? false,
      );
}

/// Evento de auditoria (acessos da conta / ações da equipe).
class SecurityEvent {
  const SecurityEvent({required this.type, this.userName, this.detail, this.ip, required this.createdAt});

  final String type;
  final String? userName;
  final String? detail;
  final String? ip;
  final DateTime createdAt;

  static const labels = {
    'LOGIN': 'Entrou',
    'LOGIN_FAILED': 'Tentativa de entrada errada',
    'LOGIN_LOCKED': 'Login travado por tentativas erradas',
    'PASSWORD_CHANGED': 'Senha trocada',
    'PASSWORD_RESET': 'Senha redefinida pelo e-mail',
    'LOGOUT_ALL': 'Saiu de todos os aparelhos',
    'TWO_FACTOR_ON': 'Verificação em duas etapas ligada',
    'TWO_FACTOR_OFF': 'Verificação em duas etapas desligada',
    'ACCOUNT_DELETED': 'Conta excluída',
    'CUSTOMER_BLOCKED': 'Cliente bloqueado',
    'CUSTOMER_UNBLOCKED': 'Cliente desbloqueado',
    'STAFF_CREATED': 'Funcionário criado',
    'STAFF_REMOVED': 'Funcionário removido',
    'STORE_CREATED': 'Loja criada',
    'STORE_SETTINGS': 'Dados da loja alterados',
    'STORE_BLOCKED': 'Loja bloqueada pela plataforma',
    'STORE_UNBLOCKED': 'Loja desbloqueada',
    'USER_BLOCKED': 'Conta bloqueada pela plataforma',
    'USER_UNBLOCKED': 'Conta desbloqueada',
    'PRODUCT_DELETED': 'Produto excluído',
    'PROMOTION_SAVED': 'Promoção salva',
  };

  String get label => labels[type] ?? type;

  bool get alarming => type == 'LOGIN_FAILED' || type == 'LOGIN_LOCKED' || type.endsWith('BLOCKED');

  factory SecurityEvent.fromJson(Map<String, dynamic> j) => SecurityEvent(
        type: j['type'] as String,
        userName: j['userName'] as String?,
        detail: j['detail'] as String?,
        ip: j['ip'] as String?,
        createdAt: _dt(j['createdAt']),
      );
}

class Promotion {
  const Promotion({
    required this.id,
    required this.title,
    this.description,
    required this.discountPercent,
    this.department,
    this.categoryId,
    this.productId,
    required this.scope,
    required this.startsAt,
    required this.endsAt,
    required this.active,
    required this.running,
    required this.notifyCustomers,
  });

  final int id;
  final String title;
  final String? description;
  final int discountPercent;
  final Department? department;
  final int? categoryId;
  final int? productId;
  final String scope;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool active;
  final bool running;
  final bool notifyCustomers;

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        id: j['id'] as int,
        title: j['title'] as String,
        description: j['description'] as String?,
        discountPercent: j['discountPercent'] as int,
        department: j['department'] == null ? null : Department.of(j['department'] as String),
        categoryId: j['categoryId'] as int?,
        productId: j['productId'] as int?,
        scope: j['scope'] as String,
        startsAt: _dt(j['startsAt']),
        endsAt: _dt(j['endsAt']),
        active: j['active'] as bool,
        running: j['running'] as bool,
        notifyCustomers: j['notifyCustomers'] as bool,
      );
}

/// Endereço salvo do cliente.
class SavedAddress {
  const SavedAddress({required this.id, required this.label, required this.address});

  final int id;
  final String label;
  final String address;

  factory SavedAddress.fromJson(Map<String, dynamic> j) =>
      SavedAddress(id: j['id'] as int, label: j['label'] as String, address: j['address'] as String);
}

/// Linha da conferência do carrinho com a loja (preço e estoque de agora).
class QuoteLine {
  const QuoteLine({required this.variantId, required this.available, required this.stock, required this.quantity, this.unitPrice});

  final int variantId;
  final bool available;
  final int stock;

  /// O que cabe no estoque (menor que o pedido = faltou peça).
  final int quantity;
  final double? unitPrice;

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
        variantId: j['variantId'] as int,
        available: j['available'] as bool,
        stock: j['stock'] as int,
        quantity: j['quantity'] as int,
        unitPrice: _dn(j['unitPrice']),
      );
}
