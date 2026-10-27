import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Canais de aviso do Android (os mesmos que o servidor indica no push).
class Channels {
  Channels._();

  static const orders = AndroidNotificationChannel(
    'pedidos',
    'Pedidos',
    description: 'Pedidos novos, mudanças de status e estoque',
    importance: Importance.high,
  );

  /// Pedido novo para a loja: toca e vibra até alguém ver (como nos apps de delivery), para não perder venda.
  static final newOrders = AndroidNotificationChannel(
    'novos_pedidos',
    'Novos pedidos',
    description: 'Alerta forte quando chega um pedido novo',
    importance: Importance.max,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 600]),
  );

  /// Corrida nova para o entregador: alerta forte (quem chega primeiro leva).
  static final jobs = AndroidNotificationChannel(
    'corridas',
    'Corridas',
    description: 'Entregas novas na sua região e avisos da corrida',
    importance: Importance.max,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
  );

  static const promotions = AndroidNotificationChannel(
    'promocoes',
    'Promoções',
    description: 'Promoções da loja e produtos que voltaram ao estoque',
    importance: Importance.high,
  );
}

/// Notificações locais: mostram o push com o app aberto e os avisos achados em segundo plano.
/// Fora do Android/iOS (testes) não faz nada.
class LocalNotifications {
  LocalNotifications._();

  static final instance = LocalNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Payload da notificação tocada (inclusive a que abriu o app): "order:12", "product:5".
  final tapped = ValueNotifier<String?>(null);

  Future<void> init() async {
    if (_ready || kIsWeb || !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      return;
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) => tapped.value = response.payload,
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(Channels.orders);
      await android?.createNotificationChannel(Channels.promotions);
      await android?.createNotificationChannel(Channels.newOrders);
      await android?.createNotificationChannel(Channels.jobs);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) tapped.value = launch!.notificationResponse?.payload;
      _ready = true;
    } catch (e) {
      debugPrint('Notificações locais indisponíveis: $e');
    }
  }

  /// Pede permissão (Android 13+ e iOS). Retorna false se a pessoa negou.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNow({
    required String key,
    required String title,
    required String body,
    String payload = '',
    AndroidNotificationChannel channel = Channels.orders,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: idFor(key),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: channel.importance == Importance.max ? Priority.max : Priority.high,
            // FLAG_INSISTENT (4): o som repete até a pessoa abrir ou dispensar (só no canal de pedido novo)
            additionalFlags: channel.id == 'novos_pedidos' ? Int32List.fromList([4]) : null,
          ),
          iOS: const DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Falha ao mostrar aviso: $e');
    }
  }

  /// Id estável (FNV-1a de 31 bits): a mesma chave nunca gera dois avisos.
  static int idFor(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}

/// Payload de toque a partir dos dados do aviso ("order:12@loja" / "product:5@loja"; a loja vai depois do @).
String payloadFor({int? orderId, int? productId, String? orderIdText, String? productIdText, String? slug, String? jobIdText}) {
  final o = orderId?.toString() ?? orderIdText;
  final p = productId?.toString() ?? productIdText;
  final at = slug == null || slug.isEmpty ? '' : '@$slug';
  if (jobIdText != null && jobIdText.isNotEmpty) return 'job:$jobIdText';
  if (o != null && o.isNotEmpty) return 'order:$o$at';
  if (p != null && p.isNotEmpty) return 'product:$p$at';
  return '';
}

/// O que um payload aponta: tipo ("order"/"product"/"job" = corrida do entregador), id e loja (pode faltar).
({String kind, int id, String? slug})? parsePayload(String payload) {
  final m = RegExp(r'^(order|product|job):(\d+)(?:@([a-z0-9-]+))?$').firstMatch(payload);
  if (m == null) return null;
  return (kind: m.group(1)!, id: int.parse(m.group(2)!), slug: m.group(3));
}
