import 'package:loja_core/loja_core.dart';

/// Chamadas da API do entregador (`/api/courier/**`), num lugar só para as telas ficarem simples.
class CourierApi {
  const CourierApi(this.api);

  final ApiClient api;

  Future<CourierProfile> me() async => CourierProfile.fromJson(await api.get('/api/courier/me') as Map<String, dynamic>);

  Future<CourierProfile> update(Map<String, dynamic> body) async =>
      CourierProfile.fromJson(await api.put('/api/courier/me', body) as Map<String, dynamic>);

  Future<CourierProfile> setOnline(bool online, GeoPoint? where) async => CourierProfile.fromJson(await api.post('/api/courier/online',
      {'online': online, if (where != null) ...{'lat': where.lat, 'lng': where.lng}}) as Map<String, dynamic>);

  Future<PageResult<CourierJobCard>> openJobs(int page, GeoPoint? where) async => PageResult.fromJson(
      await api.get('/api/courier/jobs/open?${Uri(queryParameters: {
            'page': '$page',
            if (where != null) ...{'lat': '${where.lat}', 'lng': '${where.lng}'},
          }).query}') as Map<String, dynamic>,
      CourierJobCard.fromJson);

  Future<List<CourierJob>> active() async =>
      (await api.get('/api/courier/jobs/active') as List).map((j) => CourierJob.fromJson(j as Map<String, dynamic>)).toList();

  Future<PageResult<CourierJob>> history(int page) async =>
      PageResult.fromJson(await api.get('/api/courier/jobs/history?page=$page') as Map<String, dynamic>, CourierJob.fromJson);

  Future<CourierJob> accept(int id) async => CourierJob.fromJson(await api.post('/api/courier/jobs/$id/accept') as Map<String, dynamic>);

  Future<CourierJob> pickUp(int id, String code) async =>
      CourierJob.fromJson(await api.post('/api/courier/jobs/$id/pickup', {'code': code}) as Map<String, dynamic>);

  Future<CourierJob> deliver(int id, String code) async =>
      CourierJob.fromJson(await api.post('/api/courier/jobs/$id/deliver', {'code': code}) as Map<String, dynamic>);

  /// Posição ao vivo da corrida (204). 422 = a corrida acabou.
  Future<void> sendLocation(int id, double lat, double lng) => api.post('/api/courier/jobs/$id/location', {'lat': lat, 'lng': lng});

  Future<void> cancel(int id, String? reason) => api.post('/api/courier/jobs/$id/cancel', {'reason': reason});

  Future<CourierSubscription> subscription() async =>
      CourierSubscription.fromJson(await api.get('/api/courier/subscription') as Map<String, dynamic>);

  /// Gera a cobrança da assinatura (Pix para a plataforma com um código de referência).
  Future<PaymentInstructions> checkout() async =>
      PaymentInstructions.fromJson(await api.post('/api/courier/subscription/checkout') as Map<String, dynamic>);

  Future<CourierEarnings> earnings() async =>
      CourierEarnings.fromJson(await api.get('/api/courier/earnings') as Map<String, dynamic>);
}

/// Posição do aparelho, ou nulo se não deu (sem permissão, GPS desligado, teste). Nunca lança.
Future<GeoPoint?> safeLocate() async {
  try {
    return await currentPosition();
  } catch (_) {
    return null;
  }
}
