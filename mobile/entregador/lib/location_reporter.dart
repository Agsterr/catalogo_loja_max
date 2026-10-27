import 'dart:async';

import 'package:loja_core/loja_core.dart';

/// Manda a posição do entregador para a corrida ativa a cada [every] (a loja e o cliente acompanham).
///
/// Só roda com o app em primeiro plano e com corrida ativa: [update] liga e desliga o relógio. Sem permissão de
/// localização em segundo plano e sem serviço em primeiro plano (limitação: o app precisa ficar aberto na entrega).
/// Erros de rede são ignorados; 422 (corrida acabou) tira a corrida da lista.
class LocationReporter {
  LocationReporter({required this.send, required this.locate, this.every = const Duration(seconds: 15)});

  final Future<void> Function(int jobId, double lat, double lng) send;
  final Future<GeoPoint?> Function() locate;
  final Duration every;

  final _jobs = <int>{};
  Timer? _timer;
  bool _ticking = false;

  /// Corridas que estão recebendo a posição agora.
  Set<int> get jobs => Set.unmodifiable(_jobs);

  bool get running => _timer != null;

  /// [jobIds]: corridas ativas (aceitas ou coletadas); [foreground]: app aberto à vista.
  void update(Iterable<int> jobIds, {required bool foreground}) {
    _jobs
      ..clear()
      ..addAll(jobIds);
    if (_jobs.isEmpty || !foreground) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer == null) {
      _timer = Timer.periodic(every, (_) => tick());
      tick(); // já manda a primeira posição
    }
  }

  Future<void> tick() async {
    if (_ticking || _jobs.isEmpty) return;
    _ticking = true;
    try {
      final where = await locate();
      if (where == null) return;
      for (final id in _jobs.toList()) {
        try {
          await send(id, where.lat, where.lng);
        } on ApiException catch (e) {
          if (e.status == 422 || e.status == 404) _jobs.remove(id); // a corrida acabou: para de enviar
        } catch (_) {
          // sem rede: tenta de novo no próximo ciclo
        }
      }
      if (_jobs.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    } finally {
      _ticking = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _jobs.clear();
  }
}
