// Modelos das respostas da API (mesmos nomes de campo dos DTOs do Spring).

double _d(Object? v) => v == null ? 0 : (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
DateTime _dt(Object? v) => DateTime.parse(v as String);
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    (v as List? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

enum Role { owner, staff, customer, courier, platformAdmin }

Role _role(String v) => switch (v) {
      'OWNER' => Role.owner,
      'STAFF' => Role.staff,
      'COURIER' => Role.courier,
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
  bool get isCourier => role == Role.courier;

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
  const DeliveryQuote(
      {required this.available, required this.needsLocation, this.distanceKm, this.fee, this.message, this.freight, this.freightPayer});

  final bool available;
  final bool needsLocation;
  final double? distanceKm;
  final double? fee;
  final String? message;

  /// Entregador da plataforma: frete cheio e quem paga (CUSTOMER ou STORE; [fee] já é 0 quando a loja paga).
  final double? freight;
  final String? freightPayer;

  factory DeliveryQuote.fromJson(Map<String, dynamic> j) => DeliveryQuote(
        available: j['available'] as bool,
        needsLocation: j['needsLocation'] as bool,
        distanceKm: _dn(j['distanceKm']),
        fee: _dn(j['fee']),
        message: j['message'] as String?,
        freight: _dn(j['freight']),
        freightPayer: j['freightPayer'] as String?,
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
    this.courierDelivery = false,
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

  /// Entrega feita por entregador da plataforma (taxa pela distância, calculada pelo servidor).
  final bool courierDelivery;

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
        courierDelivery: j['courierDelivery'] as bool? ?? false,
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
    this.courier,
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

  /// Entrega por entregador da plataforma (nulo nos demais pedidos).
  final CourierInfo? courier;

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
        courier: j['courier'] == null ? null : CourierInfo.fromJson(j['courier'] as Map<String, dynamic>),
      );
}

/// Situação da corrida do pedido. `pickupCode` só a loja vê; `deliveryCode` só o cliente.
class CourierInfo {
  const CourierInfo({
    required this.status,
    required this.statusLabel,
    this.courierName,
    this.courierPhone,
    this.vehicle,
    this.pickupCode,
    this.deliveryCode,
    this.expiresAt,
    this.canRetry = false,
    this.freight,
    this.freightPayer,
  });

  /// WAITING (falta pagar/confirmar), OPEN, ACCEPTED, PICKED_UP, DELIVERED, EXPIRED, CANCELED.
  final String status;
  final String statusLabel;
  final String? courierName;
  final String? courierPhone;
  final String? vehicle;
  final String? pickupCode;
  final String? deliveryCode;
  final DateTime? expiresAt;
  final bool canRetry;

  /// Frete cheio, pago direto ao entregador por [freightPayer] (CUSTOMER na entrega, STORE na coleta).
  final double? freight;
  final String? freightPayer;

  factory CourierInfo.fromJson(Map<String, dynamic> j) => CourierInfo(
        status: j['status'] as String,
        statusLabel: j['statusLabel'] as String,
        courierName: j['courierName'] as String?,
        courierPhone: j['courierPhone'] as String?,
        vehicle: j['vehicle'] as String?,
        pickupCode: j['pickupCode'] as String?,
        deliveryCode: j['deliveryCode'] as String?,
        expiresAt: j['expiresAt'] == null ? null : _dt(j['expiresAt']),
        canRetry: j['canRetry'] as bool? ?? false,
        freight: _dn(j['freight']),
        freightPayer: j['freightPayer'] as String?,
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


// --- Entregador ---

/// Veículo do entregador: valor da API e nome para mostrar.
const vehicleLabels = {'MOTO': 'Moto', 'BIKE': 'Bicicleta', 'CARRO': 'Carro', 'A_PE': 'A pé'};

class CourierProfile {
  const CourierProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicle,
    this.plate,
    required this.city,
    required this.state,
    this.baseLat,
    this.baseLng,
    required this.radiusKm,
    required this.status,
    this.statusReason,
    required this.online,
    required this.deliveredCount,
    required this.canceledCount,
    this.cpfMasked,
  });

  final int id;
  final String name;
  final String email;
  final String phone;
  final String vehicle;
  final String? plate;
  final String city;
  final String state;
  final double? baseLat;
  final double? baseLng;
  final int radiusKm;

  /// PENDING (em análise), APPROVED ou BLOCKED.
  final String status;
  final String? statusReason;
  final bool online;
  final int deliveredCount;
  final int canceledCount;

  /// "***.456.789-**" (o CPF inteiro nunca volta para o app).
  final String? cpfMasked;

  bool get approved => status == 'APPROVED';

  factory CourierProfile.fromJson(Map<String, dynamic> j) => CourierProfile(
        id: j['id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        vehicle: j['vehicle'] as String,
        plate: j['plate'] as String?,
        city: j['city'] as String,
        state: j['state'] as String,
        baseLat: _dn(j['baseLat']),
        baseLng: _dn(j['baseLng']),
        radiusKm: j['radiusKm'] as int,
        status: j['status'] as String,
        statusReason: j['statusReason'] as String?,
        online: j['online'] as bool,
        deliveredCount: j['deliveredCount'] as int,
        canceledCount: j['canceledCount'] as int,
        cpfMasked: j['cpfMasked'] as String?,
      );
}

/// Corrida no mural (sem o endereço do cliente).
class CourierJobCard {
  const CourierJobCard({
    required this.id,
    required this.storeName,
    this.pickupAddress,
    this.city,
    this.distanceToStoreKm,
    required this.tripKm,
    required this.fee,
    this.freightPayer = 'CUSTOMER',
    required this.itemCount,
    required this.expiresAt,
  });

  final int id;
  final String storeName;
  final String? pickupAddress;
  final String? city;
  final double? distanceToStoreKm;
  final double tripKm;
  final double fee;

  /// Quem paga o frete direto ao entregador: CUSTOMER (na entrega) ou STORE (na coleta).
  final String freightPayer;
  final int itemCount;
  final DateTime expiresAt;

  factory CourierJobCard.fromJson(Map<String, dynamic> j) => CourierJobCard(
        id: j['id'] as int,
        storeName: j['storeName'] as String,
        pickupAddress: j['pickupAddress'] as String?,
        city: j['city'] as String?,
        distanceToStoreKm: _dn(j['distanceToStoreKm']),
        tripKm: _d(j['tripKm']),
        fee: _d(j['fee']),
        freightPayer: j['freightPayer'] as String? ?? 'CUSTOMER',
        itemCount: j['itemCount'] as int,
        expiresAt: _dt(j['expiresAt']),
      );
}

/// Corrida do entregador (aceita, em andamento ou concluída): endereço e cliente liberados.
class CourierJob {
  const CourierJob({
    required this.id,
    required this.orderCode,
    required this.status,
    required this.statusLabel,
    required this.storeName,
    this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    this.customerName,
    this.customerPhone,
    required this.tripKm,
    required this.fee,
    this.freightPayer = 'CUSTOMER',
    required this.itemCount,
    this.deliveredAt,
  });

  final int id;
  final String orderCode;

  /// ACCEPTED, PICKED_UP, DELIVERED...
  final String status;
  final String statusLabel;
  final String storeName;
  final String? pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String? dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? customerName;
  final String? customerPhone;
  final double tripKm;
  final double fee;
  final String freightPayer;
  final int itemCount;
  final DateTime? deliveredAt;

  bool get storePays => freightPayer == 'STORE';
  bool get pickedUp => status == 'PICKED_UP';

  factory CourierJob.fromJson(Map<String, dynamic> j) => CourierJob(
        id: j['id'] as int,
        orderCode: j['orderCode'] as String,
        status: j['status'] as String,
        statusLabel: j['statusLabel'] as String,
        storeName: j['storeName'] as String,
        pickupAddress: j['pickupAddress'] as String?,
        pickupLat: _d(j['pickupLat']),
        pickupLng: _d(j['pickupLng']),
        dropoffAddress: j['dropoffAddress'] as String?,
        dropoffLat: _dn(j['dropoffLat']),
        dropoffLng: _dn(j['dropoffLng']),
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        tripKm: _d(j['tripKm']),
        fee: _d(j['fee']),
        freightPayer: j['freightPayer'] as String? ?? 'CUSTOMER',
        itemCount: j['itemCount'] as int,
        deliveredAt: j['deliveredAt'] == null ? null : _dt(j['deliveredAt']),
      );
}

class CourierEarnings {
  const CourierEarnings({required this.today, required this.week, required this.month});

  final EarningsPeriod today;
  final EarningsPeriod week;
  final EarningsPeriod month;

  factory CourierEarnings.fromJson(Map<String, dynamic> j) => CourierEarnings(
        today: EarningsPeriod.fromJson(j['today'] as Map<String, dynamic>),
        week: EarningsPeriod.fromJson(j['week'] as Map<String, dynamic>),
        month: EarningsPeriod.fromJson(j['month'] as Map<String, dynamic>),
      );
}

class EarningsPeriod {
  const EarningsPeriod(this.total, this.count);

  final double total;
  final int count;

  factory EarningsPeriod.fromJson(Map<String, dynamic> j) => EarningsPeriod(_d(j['total']), j['count'] as int);
}

/// Entregador na lista do admin da plataforma.
class AdminCourier {
  const AdminCourier({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicle,
    this.plate,
    required this.city,
    required this.state,
    required this.status,
    this.statusReason,
    required this.online,
    required this.deliveredCount,
    required this.canceledCount,
  });

  final int id;
  final String name;
  final String email;
  final String phone;
  final String vehicle;
  final String? plate;
  final String city;
  final String state;
  final String status;
  final String? statusReason;
  final bool online;
  final int deliveredCount;
  final int canceledCount;

  factory AdminCourier.fromJson(Map<String, dynamic> j) => AdminCourier(
        id: j['id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        vehicle: j['vehicle'] as String,
        plate: j['plate'] as String?,
        city: j['city'] as String,
        state: j['state'] as String,
        status: j['status'] as String,
        statusReason: j['statusReason'] as String?,
        online: j['online'] as bool,
        deliveredCount: j['deliveredCount'] as int,
        canceledCount: j['canceledCount'] as int,
      );
}


/// Assinatura do entregador: entregas grátis que sobram, mensalidade e se pode aceitar corrida agora.
class CourierSubscription {
  const CourierSubscription({
    required this.subscribed,
    this.paidUntil,
    required this.freeLeft,
    required this.freeLimit,
    required this.price,
    required this.canAccept,
  });

  final bool subscribed;
  final DateTime? paidUntil;
  final int freeLeft;
  final int freeLimit;
  final double price;
  final bool canAccept;

  factory CourierSubscription.fromJson(Map<String, dynamic> j) => CourierSubscription(
        subscribed: j['subscribed'] as bool,
        paidUntil: j['paidUntil'] == null ? null : _dt(j['paidUntil']),
        freeLeft: j['freeLeft'] as int,
        freeLimit: j['freeLimit'] as int,
        price: _d(j['price']),
        canAccept: j['canAccept'] as bool,
      );
}

/// Como pagar a assinatura (hoje: Pix para a chave da plataforma com o código de referência).
class PaymentInstructions {
  const PaymentInstructions({this.pixKey, this.holder, required this.reference, required this.amount, required this.message});

  final String? pixKey;
  final String? holder;
  final String reference;
  final double amount;
  final String message;

  bool get configured => pixKey != null && pixKey!.isNotEmpty;

  factory PaymentInstructions.fromJson(Map<String, dynamic> j) => PaymentInstructions(
        pixKey: j['pixKey'] as String?,
        holder: j['holder'] as String?,
        reference: j['reference'] as String,
        amount: _d(j['amount']),
        message: j['message'] as String,
      );
}

/// Cobrança de assinatura na lista do admin da plataforma.
class AdminPayment {
  const AdminPayment({required this.id, required this.courierId, this.courierName, required this.amount, required this.reference, required this.status, required this.createdAt});

  final int id;
  final int courierId;
  final String? courierName;
  final double amount;
  final String reference;
  final String status;
  final DateTime createdAt;

  /// Cobrança de mensalidade de loja (a lista do admin usa o mesmo cartão: o nome mostrado é o da loja).
  factory AdminPayment.fromStoreJson(Map<String, dynamic> j) => AdminPayment(
        id: j['id'] as int,
        courierId: j['storeId'] as int,
        courierName: j['storeName'] as String?,
        amount: _d(j['amount']),
        reference: j['reference'] as String,
        status: j['status'] as String,
        createdAt: _dt(j['createdAt']),
      );

  factory AdminPayment.fromJson(Map<String, dynamic> j) => AdminPayment(
        id: j['id'] as int,
        courierId: j['courierId'] as int,
        courierName: j['courierName'] as String?,
        amount: _d(j['amount']),
        reference: j['reference'] as String,
        status: j['status'] as String,
        createdAt: _dt(j['createdAt']),
      );
}

/// Mensalidade da loja: TRIAL (teste grátis), ACTIVE (paga), GRACE (vencida, ainda aparece) ou SUSPENDED (oculta para os clientes).
class StorePlan {
  const StorePlan({
    required this.state,
    required this.accessUntil,
    required this.daysLeft,
    required this.price,
    required this.visible,
    required this.trialDays,
  });

  final String state;
  final DateTime accessUntil;
  final int daysLeft;
  final double price;
  final bool visible;
  final int trialDays;

  /// Vale lembrar o dono: vence em até 7 dias, venceu ou está oculta.
  bool get needsAttention => state == 'GRACE' || state == 'SUSPENDED' || daysLeft <= 7;

  factory StorePlan.fromJson(Map<String, dynamic> j) => StorePlan(
        state: j['state'] as String,
        accessUntil: _dt(j['accessUntil']),
        daysLeft: (j['daysLeft'] as num).toInt(),
        price: _d(j['price']),
        visible: j['visible'] as bool,
        trialDays: (j['trialDays'] as num).toInt(),
      );
}
