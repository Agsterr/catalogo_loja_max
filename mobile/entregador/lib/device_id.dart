import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _key = 'device_id';

/// ID do aparelho para o cabeçalho `X-Device-Id` (o servidor guarda só uma impressão digital dele).
/// Android: ANDROID_ID (sobrevive à reinstalação); iOS: identifierForVendor; se falhar, um código aleatório guardado
/// no armazenamento seguro. [platformId] existe para os testes.
Future<String> deviceId({Future<String?> Function()? platformId}) async {
  try {
    final id = await (platformId ?? _platformId)();
    if (id != null && id.isNotEmpty) return id;
  } catch (_) {
    // sem o plugin (testes, plataforma sem suporte): usa o código guardado
  }
  const storage = FlutterSecureStorage();
  try {
    final saved = await storage.read(key: _key);
    if (saved != null && saved.isNotEmpty) return saved;
    final created = randomId();
    await storage.write(key: _key, value: created);
    return created;
  } catch (_) {
    return randomId();
  }
}

Future<String?> _platformId() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return const AndroidId().getId();
    case TargetPlatform.iOS:
      return (await DeviceInfoPlugin().iosInfo).identifierForVendor;
    default:
      return null;
  }
}

String randomId() {
  final r = Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}
