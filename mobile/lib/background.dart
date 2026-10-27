import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';

import 'api_client.dart';
import 'models.dart';
import 'notifications.dart';
import 'push.dart';
import 'session.dart';

const _task = 'avisos-da-loja';
const _lastKey = 'inbox.lastNotifiedId';
const _storage = FlutterSecureStorage();

/// Marca como já avisada a notificação do sino (o app aberto já mostrou), para o segundo plano não repetir.
Future<void> markNotified(int id) async {
  final last = int.tryParse(await _storage.read(key: _lastKey) ?? '') ?? 0;
  if (id > last) await _storage.write(key: _lastKey, value: '$id');
}

/// Confere o sino e mostra notificação para o que for novo. A primeira rodada só guarda a referência.
/// Com push ligado neste celular o servidor já avisou: aqui só avança a referência (senão chegam 2 avisos).
Future<int> notifyNewAlerts(ApiClient api, {bool viaPush = false}) async {
  final inbox = Inbox.fromJson(await api.get('/api/notifications') as Map<String, dynamic>);
  final newest = inbox.items.fold(0, (m, n) => n.id > m ? n.id : m);
  final raw = await _storage.read(key: _lastKey);
  if (raw == null) {
    await _storage.write(key: _lastKey, value: '$newest');
    return 0;
  }
  final last = int.tryParse(raw) ?? 0;
  final fresh = inbox.items.where((n) => n.id > last && !n.read).toList()..sort((a, b) => a.id.compareTo(b.id));
  for (final n in viaPush ? const <AppNotification>[] : fresh) {
    await LocalNotifications.instance.showNow(
      key: 'aviso:${n.id}',
      title: n.title,
      body: n.message,
      payload: payloadFor(orderId: n.orderId, productId: n.productId),
      channel: n.type == 'BACK_IN_STOCK' ? Channels.promotions : Channels.orders,
    );
  }
  if (newest > last) await _storage.write(key: _lastKey, value: '$newest');
  return fresh.length;
}

/// Roda em segundo plano (app fechado): entra com a sessão guardada e confere o sino.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _task) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await initializeDateFormatting('pt_BR');
      await LocalNotifications.instance.init();
      final session = Session();
      await session.restore();
      if (session.signedIn) {
        await notifyNewAlerts(session.api, viaPush: Push.configured && await session.pushToken != null);
      }
    } catch (e) {
      debugPrint('Verificação de avisos falhou: $e');
    }
    return true;
  });
}

/// Agenda a verificação periódica (Android; o sistema escolhe o momento exato para poupar bateria).
Future<void> scheduleBackgroundChecks() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      // com push ligado o servidor avisa na hora; a consulta fica só como reserva
      frequency: Push.configured ? const Duration(hours: 1) : const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } catch (e) {
    debugPrint('Não foi possível agendar a verificação de avisos: $e');
  }
}
