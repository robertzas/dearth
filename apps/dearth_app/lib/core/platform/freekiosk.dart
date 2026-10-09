import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'system_ui.dart';

/// How the last call to FreeKiosk went.
enum FreeKioskLink {
  /// Not called yet.
  unknown,
  ok,

  /// FreeKiosk holds another key (`deploy_frame.sh` says how to fix it).
  unauthorized,

  /// Nothing answered on the port.
  unreachable,
}

class FreeKioskException implements Exception {
  FreeKioskException(this.link, [this.message]);
  final FreeKioskLink link;
  final String? message;

  @override
  String toString() => 'FreeKiosk: ${link.name}${message == null ? '' : ' ($message)'}';
}

/// What FreeKiosk reports about the frame (`GET /api/status`).
class FreeKioskStatus {
  const FreeKioskStatus({this.screenOn, this.kiosk, this.model, this.android});
  final bool? screenOn;
  final bool? kiosk;
  final String? model;
  final String? android;
}

/// FreeKiosk's REST API on 127.0.0.1, for frames that run it (SPEC §13.9):
/// a real screen off and on (Device Owner `lockNow()`), status, reboot.
class FreeKiosk {
  FreeKiosk({required this.port, required this.key, http.Client? client}) : _client = client ?? http.Client();
  final int port;
  final String key;
  final http.Client _client;

  /// How the last call went (for Settings and telemetry).
  FreeKioskLink link = FreeKioskLink.unknown;

  Future<Map<String, Object?>> _call(String path, {bool post = false}) async {
    final uri = Uri.parse('http://127.0.0.1:$port$path');
    final headers = {'X-Api-Key': key};
    final http.Response res;
    try {
      res = await (post ? _client.post(uri, headers: headers) : _client.get(uri, headers: headers)).timeout(const Duration(seconds: 5));
    } on Object catch (e) {
      link = FreeKioskLink.unreachable;
      throw FreeKioskException(link, '$e');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      link = FreeKioskLink.unauthorized;
      throw FreeKioskException(link);
    }
    final body = _json(res.body);
    if (res.statusCode >= 400 || body['success'] == false) {
      link = FreeKioskLink.ok;
      throw FreeKioskException(link, '${body['error'] ?? 'HTTP ${res.statusCode}'}');
    }
    link = FreeKioskLink.ok;
    return body['data'] is Map<String, Object?> ? body['data']! as Map<String, Object?> : const {};
  }

  static Map<String, Object?> _json(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }

  Future<FreeKioskStatus> status() async {
    final d = await _call('/api/status');
    Map<String, Object?> part(String k) => d[k] is Map<String, Object?> ? d[k]! as Map<String, Object?> : const {};
    return FreeKioskStatus(
      screenOn: part('screen')['on'] as bool?,
      kiosk: part('kiosk')['enabled'] as bool?,
      model: part('device')['model'] as String?,
      android: '${part('device')['android'] ?? ''}',
    );
  }

  /// The screen physically off (SPEC FR-DSP-03): Device Owner `lockNow()`.
  Future<void> screenOff() => _call('/api/screen/off', post: true);

  Future<void> screenOn() => _call('/api/screen/on', post: true);

  /// Restarts the frame (grown-up, from Settings).
  Future<void> reboot() => _call('/api/reboot', post: true);

  void close() => _client.close();
}

/// The bridge, when `deploy_frame.sh` handed this device FreeKiosk's key;
/// null elsewhere. Invalidated when the app comes back to the front, which
/// is how a newly handed key arrives.
final freeKioskProvider = FutureProvider<FreeKiosk?>((ref) async {
  final c = await freeKioskConfig();
  if (c == null) return null;
  final k = FreeKiosk(port: c.port, key: c.key);
  ref.onDispose(k.close);
  return k;
});

/// How FreeKiosk answers right now, for Settings: the link and, when it
/// answered, its status.
final freeKioskStatusProvider = FutureProvider.autoDispose<(FreeKioskLink, FreeKioskStatus?)>((ref) async {
  final k = await ref.watch(freeKioskProvider.future);
  if (k == null) return (FreeKioskLink.unknown, null);
  try {
    final s = await k.status();
    return (k.link, s);
  } on FreeKioskException catch (e) {
    return (e.link, null);
  }
});
