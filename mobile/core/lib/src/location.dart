import 'package:geolocator/geolocator.dart';

import 'api_client.dart';

/// Posição do aparelho. A do cliente só vai na busca de lojas (nada é guardado); a do lojista vira o ponto da loja.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// Pede permissão (uma vez) e lê a posição, com precisão baixa (basta para "lojas perto de mim" e protege a privacidade).
/// Falhas viram [ApiException] com a frase para mostrar.
Future<GeoPoint> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw ApiException(0, 'Ligue a localização do aparelho para ver as lojas perto de você.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw ApiException(0, 'Sem permissão de localização. Libere nas configurações do aparelho ou escolha sua cidade.');
  }
  try {
    final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)));
    return GeoPoint(p.latitude, p.longitude);
  } catch (_) {
    throw ApiException(0, 'Não consegui pegar sua localização agora. Tente de novo ou escolha sua cidade.');
  }
}
