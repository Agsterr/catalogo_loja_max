import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models.dart';

enum SessionState { restoring, offline, signedOut, signedIn, blocked }

/// Login (cliente, equipe de uma loja ou admin da plataforma). O JWT fica no Keychain (iOS) / Keystore (Android) — a senha nunca é guardada.
/// Ao abrir o app o token é renovado (sessão deslizante de 24h); vencido, a pessoa entra de novo.
class Session extends ChangeNotifier {
  Session({http.Client? httpClient}) : _httpClient = httpClient;

  static const _tokenKey = 'jwt';
  static const _emailKey = 'last_email';
  static const pushKey = 'push_token';
  final _storage = const FlutterSecureStorage();
  final http.Client? _httpClient;

  String? _token;
  User? _user;
  SessionState state = SessionState.restoring;

  /// Motivo do bloqueio, quando [state] é [SessionState.blocked].
  String? blockedReason;

  /// Último e-mail usado, para já vir preenchido na tela de login.
  String? lastEmail;

  late final ApiClient api =
      ApiClient(token: () => _token, onUnauthorized: signOut, onAccountBlocked: _blocked, httpClient: _httpClient);

  User? get user => _user;

  bool get signedIn => state == SessionState.signedIn && _user != null;

  Future<void> restore() async {
    state = SessionState.restoring;
    notifyListeners();
    _token = await _storage.read(key: _tokenKey);
    lastEmail = await _storage.read(key: _emailKey);
    if (_token == null) {
      state = SessionState.signedOut;
    } else {
      try {
        await _authenticate(api.post('/api/me/token'), notify: false);
        _lastRefresh = DateTime.now();
      } on AccountBlockedException {
        return; // _blocked já trocou o estado e limpou a sessão
      } on ApiException catch (e) {
        state = e.status == 0 ? SessionState.offline : SessionState.signedOut;
        if (state == SessionState.signedOut) await _storage.delete(key: _tokenKey);
      }
    }
    notifyListeners();
  }

  /// Com a verificação em duas etapas ligada, a primeira tentativa sem [code] lança [ApiException] com
  /// `code == 'TOTP_REQUIRED'` (a tela então pede o código do autenticador).
  DateTime? _lastRefresh;

  /// Renova o token (sessão de 24h deslizante). Chamado ao voltar para o app: quem deixa o app aberto em segundo
  /// plano por mais de um dia não é deslogado. Sem rede ou sem login, não faz nada.
  Future<void> refreshIfDue() async {
    if (state != SessionState.signedIn) return;
    final last = _lastRefresh;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return;
    try {
      await _authenticate(api.post('/api/me/token'), notify: false);
      _lastRefresh = DateTime.now();
    } on ApiException {
      // sem rede: tenta de novo na próxima vez; 401/bloqueio já derrubam a sessão pelo ApiClient
    }
  }

  Future<void> login(String email, String password, {String? code}) async {
    await _authenticate(api.post('/api/auth/login', {
      'email': email.trim(),
      'password': password,
      if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
    }));
    lastEmail = email.trim();
    await _storage.write(key: _emailKey, value: lastEmail);
  }

  Future<void> register({required String name, required String email, String? phone, required String password}) async {
    await _authenticate(api.post('/api/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'password': password,
    }));
    lastEmail = email.trim();
    await _storage.write(key: _emailKey, value: lastEmail);
  }

  /// Lojista abre a loja na plataforma e entra como dono.
  Future<void> registerStore({
    required String storeName,
    required String slug,
    required String ownerName,
    required String email,
    required String password,
  }) async {
    await _authenticate(api.post('/api/auth/register-store', {
      'storeName': storeName.trim(),
      'slug': slug.trim(),
      'ownerName': ownerName.trim(),
      'email': email.trim(),
      'password': password,
    }));
    lastEmail = email.trim();
    await _storage.write(key: _emailKey, value: lastEmail);
  }

  /// Dados da conta de novo (ex.: depois de ligar a verificação em duas etapas).
  Future<void> reloadUser() async {
    _user = User.fromJson(await api.get('/api/me') as Map<String, dynamic>);
    notifyListeners();
  }

  /// Troca a senha: as outras sessões caem e este aparelho recebe um token novo.
  Future<void> changePassword(String current, String next) =>
      _authenticate(api.post('/api/me/password', {'currentPassword': current, 'newPassword': next}));

  Future<void> updateProfile(String name, String? phone) async {
    _user = User.fromJson(await api.put('/api/me', {'name': name, 'phone': phone}) as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> _authenticate(Future<dynamic> request, {bool notify = true}) async {
    final json = await request as Map<String, dynamic>;
    _token = json['token'] as String;
    _user = User.fromJson(json['user'] as Map<String, dynamic>);
    await _storage.write(key: _tokenKey, value: _token);
    state = SessionState.signedIn;
    if (notify) notifyListeners();
  }

  /// "Sair" pedido pela pessoa: antes de limpar a sessão, tira este celular dos avisos da conta.
  Future<void> logout({bool everywhere = false}) async {
    if (state == SessionState.signedIn) {
      try {
        final push = await pushToken;
        if (push != null) await api.post('/api/me/push-token/remove', {'token': push});
        if (everywhere) await api.post('/api/me/logout-all');
      } catch (_) {
        // sem rede: o servidor descarta o celular quando o Firebase recusar o aviso
      }
    }
    await signOut();
  }

  Future<void> rememberPushToken(String token) => _storage.write(key: pushKey, value: token);

  Future<String?> get pushToken => _storage.read(key: pushKey);

  Future<void> signOut() async {
    _token = null;
    _user = null;
    blockedReason = null;
    await _storage.delete(key: _tokenKey);
    state = SessionState.signedOut;
    notifyListeners();
  }

  /// API respondeu 403 ACCOUNT_BLOCKED (qualquer requisição, inclusive o login): derruba a sessão
  /// e mostra a tela de bloqueio até tocar em "Sair".
  void _blocked(String reason) {
    _token = null;
    _user = null;
    blockedReason = reason;
    state = SessionState.blocked;
    notifyListeners();
    _storage.delete(key: _tokenKey).catchError((Object _) {});
  }

  /// Exclusão de conta (exigência das lojas / LGPD).
  Future<void> deleteAccount(String password) async {
    await api.post('/api/me/delete', {'password': password});
    await signOut();
  }
}
