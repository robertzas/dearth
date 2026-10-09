import 'dart:async';
import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A failed Hub call with the server's stable error code (SPEC §14.2).
class HubApiException implements Exception {
  HubApiException(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;

  bool get isAuth => status == 401 || status == 403;
  bool get isNetwork => status == 0;

  /// Text fit for a toast or an inline error.
  String get friendly => message ?? switch (code) {
        'network' => 'Can’t reach the Hub. Check the address and that it’s running.',
        'unauthorized' => 'This device isn’t paired with the Hub anymore.',
        'forbidden' => 'That password didn’t work.',
        'invalid_code' => 'That code is unknown, used or expired.',
        _ => 'The Hub said: $code',
      };

  @override
  String toString() => 'HubApiException($status $code${message == null ? '' : ': $message'})';
}

/// Pairing handshake started by a new device (SPEC §9.2).
@immutable
class PairingTicket {
  const PairingTicket({required this.pairingId, required this.code, required this.secret, required this.approveUrl});
  final String pairingId;
  final String code;
  final String secret;
  final String approveUrl;
}

/// Pairing status as polled by the waiting device.
@immutable
class PairResult {
  const PairResult({required this.status, this.token, this.deviceId, this.role, this.admin = false});
  factory PairResult.fromJson(Map<String, Object?> j) => PairResult(
        status: j['status'] as String? ?? 'unknown',
        token: j['token'] as String?,
        deviceId: j['deviceId'] as String?,
        role: j['role'] as String?,
        admin: j['admin'] as bool? ?? false,
      );
  final String status;
  final String? token;
  final String? deviceId;
  final String? role;
  final bool admin;

  bool get approved => status == 'approved' && token != null && deviceId != null;
}

/// Thin HTTP client for the Hub API. All requests time out; network failures
/// surface as [HubApiException] with code `network`.
class HubApi {
  HubApi(this.base, {this.token, this.adminPassword, http.Client? client}) : _client = client ?? http.Client();

  /// Normalizes user input ("10.0.1.20:8080", "dearth.example.com") to a base URL.
  static Uri? parseBase(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || !(u.isScheme('http') || u.isScheme('https'))) return null;
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null);
  }

  final Uri base;
  String? token;

  /// Sent with every request when set: admin calls on a Hub where this
  /// device isn't an admin (moving a household, SPEC §7.2).
  final String? adminPassword;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Uri get wsUri => base.replace(scheme: base.isScheme('https') ? 'wss' : 'ws', path: '/api/sync');

  Uri _u(String path, [Map<String, String>? query]) => base.replace(path: path, queryParameters: query == null || query.isEmpty ? null : query);

  Map<String, String> _headers({bool json = true, String? admin}) => {
        if (json) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
        'x-dearth-admin': ?(admin ?? adminPassword),
      };

  Future<Object?> _send(Future<http.Response> Function() call, {Duration timeout = _timeout}) async {
    final http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw HubApiException(0, 'network', 'The Hub didn’t answer in time.');
    } on Object {
      throw HubApiException(0, 'network');
    }
    final body = res.body.isEmpty ? null : _tryJson(res.body);
    if (res.statusCode >= 400) {
      final m = body is Map<String, Object?> ? body : const <String, Object?>{};
      throw HubApiException(res.statusCode, m['error'] as String? ?? 'http_${res.statusCode}', m['message'] as String?);
    }
    return body;
  }

  static Object? _tryJson(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, Object?>> _getJson(String path, [Map<String, String>? query]) async =>
      (await _send(() => _client.get(_u(path, query), headers: _headers(json: false)))) as Map<String, Object?>? ?? const {};

  Future<Map<String, Object?>> _postJson(String path, Map<String, Object?> body, {String? admin}) async =>
      (await _send(() => _client.post(_u(path), headers: _headers(admin: admin), body: jsonEncode(body)))) as Map<String, Object?>? ?? const {};

  // ── Health & pairing ────────────────────────────────────────────────────

  Future<Map<String, Object?>> health() => _getJson('/api/health');

  Future<PairingTicket> startPairing({required String name, required String platform, String? model, String? role}) async {
    final j = await _postJson('/api/pair/start', {'name': name, 'platform': platform, 'model': ?model, 'role': ?role});
    return PairingTicket(
      pairingId: j['pairingId']! as String,
      code: j['code']! as String,
      secret: j['secret']! as String,
      approveUrl: j['approveUrl'] as String? ?? '',
    );
  }

  Future<PairResult> pairingStatus(PairingTicket t) async =>
      PairResult.fromJson(await _postJson('/api/pair/status', {'pairingId': t.pairingId, 'secret': t.secret}));

  /// Redeems a pre-approved enrollment code.
  Future<PairResult> claim(String code, {required String platform, String? name}) async =>
      PairResult.fromJson(await _postJson('/api/pair/claim', {'code': code, 'platform': platform, 'name': ?name}));

  /// Approves a pending pairing with the Hub's admin password (first device).
  Future<void> approveWithPassword(String password, String code, {String? role, bool admin = true, String? name}) =>
      _postJson('/api/admin/pair/approve', {'code': code, 'role': ?role, 'admin': admin, 'name': ?name}, admin: password);

  // ── Sync bootstrap (SPEC §8.4.6) ────────────────────────────────────────

  /// Downloads and decodes the role-scoped snapshot off the UI isolate.
  Future<Map<String, Object?>> snapshot() async {
    final http.Response res;
    try {
      res = await _client.get(_u('/api/sync/snapshot'), headers: _headers(json: false)).timeout(const Duration(seconds: 60));
    } on Object {
      throw HubApiException(0, 'network');
    }
    if (res.statusCode >= 400) throw HubApiException(res.statusCode, res.statusCode == 401 ? 'unauthorized' : 'snapshot_failed');
    return compute(_decodeMap, res.body);
  }

  static Map<String, Object?> _decodeMap(String s) => jsonDecode(s) as Map<String, Object?>;

  // ── Blobs ───────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> uploadBlob(Uint8List bytes, String mime, {bool normalize = false}) async {
    final res = await _send(() => _client.post(
          _u('/api/blobs', normalize ? {'normalize': '1'} : null),
          headers: {'content-type': mime, if (token != null) 'authorization': 'Bearer $token'},
          body: bytes,
        ));
    return res as Map<String, Object?>? ?? const {};
  }

  /// URL of a blob (or a sized variant). Content-addressed, so no token.
  Uri blobUrl(String sha, {int? width, int? height, bool cover = false, bool blur = false}) => _u('/api/blobs/$sha', {
        if (width != null) 'w': '$width',
        if (height != null) 'h': '$height',
        if (cover) 'fit': 'cover',
        if (blur) 'blur': '1',
      });

  /// Cached, resized copy of a remote image (recipe photos, album art).
  Uri imageProxy(String url, {int? width, int? height, bool cover = false}) => _u('/api/img', {
        'u': url,
        if (width != null) 'w': '$width',
        if (height != null) 'h': '$height',
        if (cover) 'fit': 'cover',
        't': ?token,
      });

  // ── Feature endpoints ───────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> getList(String path, [Map<String, String>? query]) async {
    final res = await _send(() => _client.get(_u(path, query), headers: _headers(json: false)));
    return [for (final e in (res as List? ?? const [])) if (e is Map<String, Object?>) e];
  }

  Future<Map<String, Object?>> post(String path, Map<String, Object?> body) => _postJson(path, body);

  Future<List<String>> getStrings(String path, [Map<String, String>? query]) async {
    final res = await _send(() => _client.get(_u(path, query), headers: _headers(json: false)));
    return [for (final e in (res as List? ?? const [])) '$e'];
  }

  Future<List<Map<String, Object?>>> postList(String path, Map<String, Object?> body) async {
    final res = await _send(() => _client.post(_u(path), headers: _headers(), body: jsonEncode(body)));
    return [for (final e in (res as List? ?? const [])) if (e is Map<String, Object?>) e];
  }

  Future<Map<String, Object?>> get(String path, [Map<String, String>? query]) => _getJson(path, query);

  Future<Map<String, Object?>> put(String path, Map<String, Object?> body) async =>
      (await _send(() => _client.put(_u(path), headers: _headers(), body: jsonEncode(body)))) as Map<String, Object?>? ?? const {};

  Future<void> delete(String path) => _send(() => _client.delete(_u(path), headers: _headers(json: false)));

  // ── Moving a household between Hubs (SPEC §7.2, §8.7; admin) ───────────

  /// Every synced table plus the blobs the rows point at, decoded off the
  /// UI isolate.
  Future<Map<String, Object?>> exportHousehold() async {
    final http.Response res;
    try {
      res = await _client.get(_u('/api/admin/export', {'blobs': '1'}), headers: _headers(json: false)).timeout(const Duration(minutes: 2));
    } on Object {
      throw HubApiException(0, 'network');
    }
    if (res.statusCode >= 400) {
      final m = _tryJson(res.body);
      throw HubApiException(res.statusCode, m is Map<String, Object?> ? m['error'] as String? ?? 'export_failed' : 'export_failed', m is Map<String, Object?> ? m['message'] as String? : null);
    }
    return compute(_decodeMap, res.body);
  }

  /// Writes an export into this Hub; its rows take over (returns the op count).
  Future<int> importHousehold(Map<String, Object?> export) async {
    final body = await compute(jsonEncode, {'schema': export['schema'], 'tables': export['tables']});
    final res = await _send(() => _client.post(_u('/api/admin/import'), headers: _headers(), body: body), timeout: const Duration(minutes: 10));
    return ((res as Map<String, Object?>?)?['ops'] as num?)?.toInt() ?? 0;
  }

  Future<List<String>> missingBlobs(List<String> shas) async {
    final r = await _postJson('/api/admin/blobs/missing', {'shas': shas});
    return [for (final s in r['missing'] as List? ?? const []) '$s'];
  }

  /// A blob exactly as stored (no variant).
  Future<Uint8List> blobBytes(String sha) async {
    final http.Response res;
    try {
      res = await _client.get(_u('/api/blobs/$sha')).timeout(const Duration(minutes: 2));
    } on Object {
      throw HubApiException(0, 'network');
    }
    if (res.statusCode >= 400) throw HubApiException(res.statusCode, 'blob_missing');
    return res.bodyBytes;
  }

  Future<void> putBlob(String sha, Uint8List bytes, {required String mime, String? origin}) => _send(
        () => _client.put(_u('/api/admin/blobs/$sha', origin == null ? null : {'origin': origin}), headers: {..._headers(json: false), 'content-type': mime}, body: bytes),
        timeout: const Duration(minutes: 2),
      );

  void close() => _client.close();
}

/// Normalized blob reference stored on rows (`{sha, mime, w, h, bytes}`).
String? blobSha(String? ref) {
  if (ref == null || ref.isEmpty) return null;
  if (RegExp(r'^[a-f0-9]{64}$').hasMatch(ref)) return ref;
  return decodeJsonMap(ref)['sha'] as String?;
}
