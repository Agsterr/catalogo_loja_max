import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'notifications.dart';
import 'session.dart';

/// Push pelo Firebase, igual ao Gerenciamento Max: o servidor avisa na hora (pedido novo, status do pedido,
/// estoque baixo, promoção das lojas que a pessoa segue, produto que voltou), mesmo com o app fechado, e o app confirma o recebimento.
/// A configuração vem do build (`--dart-define=FIREBASE_*`); sem ela o app segue só com a consulta periódica
/// em segundo plano (background.dart).
class Push {
  Push._();

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get configured =>
      _apiKey.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty && _projectId.isNotEmpty && !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  static const options = FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId);

  static const _askedKey = 'asked_notifications';
  static bool _started = false;
  static Session? _session;

  /// Android 13+ só mostra notificação depois que a pessoa permite: pede uma vez, ao abrir o app.
  static Future<void> askPermissionOnce() async {
    const storage = FlutterSecureStorage();
    try {
      if (await storage.read(key: _askedKey) != null) return;
      await LocalNotifications.instance.requestPermission();
      await storage.write(key: _askedKey, value: '1');
    } catch (_) {
      // sem permissão ou sem storage: o app segue, só não mostra o aviso
    }
  }

  /// Ao abrir o app: pega o código do celular no Firebase e trata as mensagens. Sem login o celular
  /// recebe só promoções; ao entrar, passa a receber também os avisos da conta ([register]).
  static Future<void> start(Session session) async {
    _session = session;
    if (!configured || _started) return;
    _started = true;
    try {
      await Firebase.initializeApp(options: options);
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_onBackground);
      // app aberto: o Android não mostra sozinho, então mostra como aviso local
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _opened(initial);

      // Código clássico do FCM (campo "token" da API v1 que o servidor usa).
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) await _remember(token);
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen(_remember);
      session.addListener(register);
    } catch (e) {
      _started = false;
      debugPrint('Push indisponível: $e');
    }
  }

  static Future<void> _remember(String token) async {
    await _session?.rememberPushToken(token);
    await register();
  }

  static String? _following;

  /// Liga o celular à conta logada (avisos dos pedidos / da loja da equipe) e à loja aberta (promoções).
  static Future<void> register() async {
    final session = _session;
    if (session == null) return;
    final token = await session.pushToken;
    if (token == null) return;
    try {
      if (session.signedIn) await session.api.post('/api/me/push-token', {'token': token});
    } catch (_) {
      // sem rede agora: tenta de novo na próxima abertura
    }
    final slug = _following;
    if (slug != null) await follow(slug);
  }

  /// Cliente abriu a vitrine de uma loja: passa a receber as promoções dela (com ou sem login).
  static Future<void> follow(String slug) async {
    _following = slug;
    final token = await _session?.pushToken;
    if (token == null) return;
    try {
      await ApiClient().post('/api/public/stores/$slug/push', {'token': token});
    } catch (_) {
      // sem rede: segue na próxima abertura
    }
  }

  /// Liga/desliga as promoções neste celular.
  static Future<void> setPromotions(Session session, bool enabled) async {
    final token = await session.pushToken;
    if (token == null || !session.signedIn) return;
    await session.api.put('/api/me/push-preferences', {'token': token, 'promoNotifications': enabled});
  }

  static Future<void> _ack(RemoteMessage m) async =>
      ackPush(m.data['messageId'] as String?, await const FlutterSecureStorage().read(key: Session.pushKey));

  static String _payload(RemoteMessage m) =>
      payloadFor(
          orderIdText: m.data['orderId'] as String?,
          productIdText: m.data['productId'] as String?,
          slug: m.data['slug'] as String?);

  static Future<void> _opened(RemoteMessage m) async {
    await _ack(m);
    final payload = _payload(m);
    if (payload.isNotEmpty) LocalNotifications.instance.tapped.value = payload;
  }

  static Future<void> _showForeground(RemoteMessage m) async {
    await _ack(m);
    final n = m.notification;
    if (n == null) return;
    final promo = m.data['type'] == 'promotion' || m.data['type'] == 'back_in_stock';
    await LocalNotifications.instance.showNow(
      key: 'push:${m.messageId}',
      title: n.title ?? 'Loja Max',
      body: n.body ?? '',
      payload: _payload(m),
      channel: promo ? Channels.promotions : Channels.orders,
    );
  }
}

/// Mensagem com o app fechado: o Android já mostrou a notificação; só confirma o recebimento.
@pragma('vm:entry-point')
Future<void> _onBackground(RemoteMessage m) async {
  await ackPush(m.data['messageId'] as String?, await const FlutterSecureStorage().read(key: Session.pushKey));
}
