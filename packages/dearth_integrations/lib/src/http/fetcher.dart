import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Error from a provider call, classified for retry/backoff decisions.
class ProviderException implements Exception {
  ProviderException(this.provider, this.message, {this.status, this.retryAfter, this.body});

  final String provider;
  final String message;
  final int? status;
  final Duration? retryAfter;
  final String? body;

  bool get isAuth => status == 401 || status == 403;
  bool get isNotFound => status == 404;
  bool get isRateLimited => status == 429;
  bool get isRetryable => status == null || status == 429 || status! >= 500;

  @override
  String toString() => 'ProviderException($provider${status == null ? '' : ' $status'}): $message';
}

/// Thin HTTP layer shared by every adapter (SPEC §13.1): timeouts, a
/// descriptive User-Agent, JSON decoding, bounded retries with jitter for
/// transient failures, and `Retry-After` support. Tests inject a
/// `MockClient`, so no adapter ever needs the network in CI.
class Fetcher {
  Fetcher({
    http.Client? client,
    this.userAgent = 'Dearth/0.1 (+https://github.com/robertzas/dearth)',
    this.timeout = const Duration(seconds: 20),
    this.maxRetries = 2,
    Future<void> Function(Duration)? sleep,
  })  : client = client ?? http.Client(),
        _sleep = sleep ?? Future<void>.delayed;

  final http.Client client;
  final String userAgent;
  final Duration timeout;
  final int maxRetries;
  final Future<void> Function(Duration) _sleep;
  final math.Random _random = math.Random();

  Future<http.Response> send(
    String provider,
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    bool retry = true,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      http.Response res;
      try {
        final req = http.Request(method, uri)
          ..headers.addAll({'User-Agent': userAgent, 'Accept': 'application/json', ...?headers});
        if (body is String) {
          req.body = body;
        } else if (body is List<int>) {
          req.bodyBytes = body;
        } else if (body is Map<String, String>) {
          req.bodyFields = body;
        } else if (body != null) {
          req.headers['Content-Type'] = 'application/json';
          req.body = jsonEncode(body);
        }
        res = await http.Response.fromStream(await client.send(req).timeout(timeout));
      } on TimeoutException {
        if (retry && attempt <= maxRetries) {
          await _sleep(_backoff(attempt));
          continue;
        }
        throw ProviderException(provider, 'Timed out after ${timeout.inSeconds}s');
      } on http.ClientException catch (e) {
        if (retry && attempt <= maxRetries) {
          await _sleep(_backoff(attempt));
          continue;
        }
        throw ProviderException(provider, 'Network error: ${e.message}');
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return res;
      final retryAfter = _retryAfter(res.headers['retry-after']);
      final ex = ProviderException(
        provider,
        'HTTP ${res.statusCode} from ${uri.host}${uri.path}',
        status: res.statusCode,
        retryAfter: retryAfter,
        body: res.body.length > 500 ? res.body.substring(0, 500) : res.body,
      );
      if (retry && ex.isRetryable && attempt <= maxRetries) {
        await _sleep(retryAfter != null && retryAfter < const Duration(seconds: 30) ? retryAfter : _backoff(attempt));
        continue;
      }
      throw ex;
    }
  }

  Future<Object?> getJson(String provider, Uri uri, {Map<String, String>? headers}) async =>
      _decode(provider, await send(provider, 'GET', uri, headers: headers));

  Future<Object?> postJson(String provider, Uri uri, {Map<String, String>? headers, Object? body}) async =>
      _decode(provider, await send(provider, 'POST', uri, headers: headers, body: body));

  Future<String> getText(String provider, Uri uri, {Map<String, String>? headers}) async =>
      (await send(provider, 'GET', uri, headers: {'Accept': '*/*', ...?headers})).body;

  /// Decodes a response body as JSON (public for adapters that need headers).
  Object? decodeResponse(String provider, http.Response res) => _decode(provider, res);

  Object? _decode(String provider, http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } on FormatException {
      throw ProviderException(provider, 'Invalid JSON from ${res.request?.url.host}', status: res.statusCode);
    }
  }

  Duration _backoff(int attempt) {
    final base = 400 * math.pow(2, attempt - 1);
    return Duration(milliseconds: base.toInt() + _random.nextInt(250));
  }

  static Duration? _retryAfter(String? header) {
    if (header == null) return null;
    final secs = int.tryParse(header.trim());
    return secs == null ? null : Duration(seconds: secs);
  }

  void close() => client.close();
}

/// Reads a map that must be a JSON object.
Map<String, Object?> asObject(Object? v, String provider) {
  if (v is Map<String, Object?>) return v;
  throw ProviderException(provider, 'Expected a JSON object');
}

List<Object?> asArray(Object? v) => v is List ? v : const [];
