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
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
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

/// Payload de toque a partir dos dados do aviso ("order:12" / "product:5").
String payloadFor({int? orderId, int? productId, String? orderIdText, String? productIdText}) {
  final o = orderId?.toString() ?? orderIdText;
  final p = productId?.toString() ?? productIdText;
  if (o != null && o.isNotEmpty) return 'order:$o';
  if (p != null && p.isNotEmpty) return 'product:$p';
  return '';
}
