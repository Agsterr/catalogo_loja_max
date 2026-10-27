import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code});

  final int status;
  final String message;

  /// Campo `code` do ProblemDetail, quando a API manda (ex.: `ACCOUNT_BLOCKED`).
  final String? code;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Conta bloqueada pela loja: 403 com `"code": "ACCOUNT_BLOCKED"`.
/// [message] é o motivo (`detail` do ProblemDetail).
class AccountBlockedException extends ApiException {
  AccountBlockedException(String reason) : super(403, reason, code: codeValue);

  static const codeValue = 'ACCOUNT_BLOCKED';
  static const defaultReason = 'Sua conta foi bloqueada.';
}

/// Cliente HTTP mínimo para a API. Converte erros (ProblemDetail) em [ApiException].
class ApiClient {
  ApiClient(
      {String? baseUrl,
      this.token,
      this.onUnauthorized,
      this.onAccountBlocked,
      this.reauthenticate,
      http.Client? httpClient})
      : baseUrl = baseUrl ?? AppConfig.apiUrl,
        _http = httpClient ?? http.Client();

  /// Chamado (antes de lançar [AccountBlockedException]) quando a API diz que a conta está bloqueada —
  /// em qualquer requisição, inclusive no login. Recebe o motivo.
  final void Function(String reason)? onAccountBlocked;

  final String baseUrl;
  final http.Client _http;

  /// Retorna o token JWT atual. Nulo = requisição anônima (vitrine sem login).
  final String? Function()? token;

  /// Chamado quando a API responde 401 com token (sessão expirada).
  final void Function()? onUnauthorized;

  /// Chamado no 401 com token: se conseguir uma sessão nova devolve true e a requisição é repetida uma vez.
  final Future<bool> Function()? reauthenticate;

  static const _timeout = Duration(seconds: 20);

  Future<dynamic> get(String path) => _send('GET', path);

  /// Baixa um arquivo (planilha) com o login da pessoa.
  Future<List<int>> getBytes(String path) async {
    final jwt = token?.call();
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl$path'), headers: {if (jwt != null) 'Authorization': 'Bearer $jwt'})
          .timeout(const Duration(seconds: 60));
      if (res.statusCode / 100 != 2) throw ApiException(res.statusCode, 'Não foi possível baixar o arquivo.');
      return res.bodyBytes;
    } on TimeoutException {
      throw ApiException(0, 'O servidor demorou para responder. Tente novamente.');
    } on SocketException {
      throw ApiException(0, 'Sem conexão com a internet.');
    }
  }

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body ?? const {});

  Future<dynamic> put(String path, Object body) => _send('PUT', path, body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Envio de arquivo (multipart/form-data), ex.: fotos dos produtos.
  Future<dynamic> upload(String path,
      {required List<int> bytes, required String filename, String field = 'file', Map<String, String> fields = const {}}) {
    return _execute(
      () => http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename)),
      timeout: const Duration(seconds: 90),
    );
  }

  Future<dynamic> _send(String method, String path, [Object? body]) {
    return _execute(() {
      final request = http.Request(method, Uri.parse('$baseUrl$path'));
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return request;
    });
  }

  /// [build] cria a requisição de novo a cada tentativa (uma requisição HTTP não pode ser reenviada).
  Future<dynamic> _execute(http.BaseRequest Function() build, {Duration timeout = _timeout, bool retried = false}) async {
    final request = build();
    final jwt = token?.call();
    if (jwt != null) request.headers['Authorization'] = 'Bearer $jwt';
    request.headers['Accept'] = 'application/json';

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw ApiException(0, 'O servidor demorou para responder. Tente novamente.');
    } on SocketException {
      throw ApiException(0, 'Sem conexão com a internet.');
    } on http.ClientException {
      throw ApiException(0, 'Não foi possível conectar ao servidor.');
    }

    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    final problem = _problem(text);
    if (res.statusCode == 403 && problem?['code'] == AccountBlockedException.codeValue) {
      final detail = problem?['detail'];
      final reason = detail is String && detail.trim().isNotEmpty ? detail.trim() : AccountBlockedException.defaultReason;
      onAccountBlocked?.call(reason);
      throw AccountBlockedException(reason);
    }
    if (res.statusCode == 401 && jwt != null) {
      if (!retried && reauthenticate != null && await reauthenticate!()) {
        return _execute(build, timeout: timeout, retried: true);
      }
      onUnauthorized?.call();
    }
    final code = problem?['code'];
    throw ApiException(res.statusCode, _message(problem, res.statusCode), code: code is String ? code : null);
  }

  static Map<String, dynamic>? _problem(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) return json;
    } catch (_) {}
    return null;
  }

  static String _message(Map<String, dynamic>? problem, int status) {
    if (problem?['detail'] is String) return problem!['detail'] as String;
    return switch (status) {
      401 => 'Sessão expirada. Entre novamente.',
      403 => 'Você não tem permissão para isso.',
      404 => 'Não encontrado.',
      _ => 'Erro inesperado ($status).',
    };
  }
}

/// Confirma ao servidor que o aviso (push) chegou ao celular. Não precisa de login: vale com o código
/// do aviso e o do celular que o próprio servidor mandou. Falha em silêncio (o servidor só registra).
Future<void> ackPush(String? messageId, String? deviceToken, {ApiClient? api}) async {
  if (messageId == null || messageId.isEmpty || deviceToken == null || deviceToken.isEmpty) return;
  try {
    await (api ?? ApiClient()).post('/api/push/ack', {'id': messageId, 'token': deviceToken});
  } catch (_) {
    // sem rede agora: o aviso já foi entregue; a confirmação é só um registro
  }
}
