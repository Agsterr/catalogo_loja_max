/// Configuração por ambiente, via `--dart-define`.
///
/// Ex.: `flutter run --dart-define=API_URL=http://10.0.2.2:8080` (emulador Android)
/// e `flutter build appbundle --dart-define=API_URL=https://api.seudominio.com.br`.
class AppConfig {
  AppConfig._();

  /// URL da API Spring Boot. Em produção deve ser HTTPS (o release do Android recusa HTTP).
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');

  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'contato@lojamax.com.br');
}
