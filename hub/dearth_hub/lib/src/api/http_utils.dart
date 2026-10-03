import 'dart:convert';

import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import '../auth.dart';
import '../kernel.dart';

final _log = Logger('http');

/// An error with an HTTP status and a stable machine-readable code.
class HttpError implements Exception {
  HttpError(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;
  @override
  String toString() => 'HttpError($status $code${message == null ? '' : ': $message'})';
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'};

Response jsonOk(Object? body, {int status = 200}) => Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Response jsonError(int status, String code, [String? message]) =>
    Response(status, body: jsonEncode({'error': code, 'message': ?message}), headers: _jsonHeaders);

Future<Map<String, Object?>> readJson(Request r, {int maxBytes = 1 << 20}) async {
  final bytes = <int>[];
  await for (final chunk in r.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) throw HttpError(413, 'too_large');
  }
  if (bytes.isEmpty) return const {};
  try {
    final v = jsonDecode(utf8.decode(bytes));
    if (v is Map<String, Object?>) return v;
  } on FormatException {
    // fall through
  }
  throw HttpError(400, 'bad_json');
}

String? bearerToken(Request r) {
  final h = r.headers['authorization'];
  if (h != null && h.toLowerCase().startsWith('bearer ')) return h.substring(7).trim();
  return r.url.queryParameters['t'];
}

/// Resolves the calling device or throws 401.
Future<DeviceIdentity> requireDevice(Request r, HubAuth auth) async {
  final id = await auth.deviceForToken(bearerToken(r));
  if (id == null) throw HttpError(401, 'unauthorized', 'Pair this device first');
  return id;
}

/// Admin = an admin device token, or the admin password (scripts, first run).
Future<DeviceIdentity> requireAdmin(Request r, HubAuth auth) async {
  final pw = r.headers['x-dearth-admin'];
  if (pw != null && pw.isNotEmpty) {
    if (await auth.checkAdminPassword(pw)) return DeviceIdentity.hub;
    throw HttpError(403, 'forbidden', 'Wrong admin password');
  }
  final id = await requireDevice(r, auth);
  if (!id.admin) throw HttpError(403, 'forbidden', 'This device is not an admin device');
  return id;
}

Middleware errorMiddleware() => (inner) => (request) async {
      try {
        return await inner(request);
      } on HijackException {
        rethrow; // WebSocket upgrades hijack the connection
      } on HttpError catch (e) {
        return jsonError(e.status, e.code, e.message);
      } on ProviderException catch (e) {
        _log.info('${request.method} /${request.url.path}: $e');
        return jsonError(e.isAuth ? 424 : 502, 'provider_error', e.message);
      } on FormatException catch (e) {
        return jsonError(400, 'bad_request', e.message);
      } on StateError catch (e) {
        return jsonError(409, 'conflict', e.message);
      } on Object catch (e, st) {
        _log.severe('Unhandled error on ${request.method} /${request.url.path}', e, st);
        return jsonError(500, 'internal', 'Something went wrong');
      }
    };

/// Same-origin by default; allows configured origins and local dev servers.
Middleware corsMiddleware(Set<String> allowed) => (inner) => (request) async {
      final origin = request.headers['origin'];
      final ok = origin != null &&
          (allowed.contains(origin) || RegExp(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?$').hasMatch(origin));
      Map<String, String> headers() => {
            if (ok) 'access-control-allow-origin': origin,
            if (ok) 'vary': 'Origin',
            if (ok) 'access-control-allow-headers': 'authorization, content-type, x-dearth-admin',
            if (ok) 'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
            if (ok) 'access-control-max-age': '600',
          };
      if (request.method == 'OPTIONS') return Response(ok ? 204 : 403, headers: headers());
      final res = await inner(request);
      return res.change(headers: headers());
    };

Middleware securityHeaders() => (inner) => (request) async {
      final res = await inner(request);
      return res.change(headers: {
        'x-content-type-options': 'nosniff',
        'referrer-policy': 'same-origin',
        'x-frame-options': 'SAMEORIGIN',
      });
    };

Middleware requestLog() => (inner) => (request) async {
      final sw = Stopwatch()..start();
      final res = await inner(request);
      if (!request.url.path.startsWith('api/blobs') || res.statusCode >= 400) {
        _log.fine('${request.method} /${request.url.path} → ${res.statusCode} (${sw.elapsedMilliseconds} ms)');
      }
      return res;
    };

/// Small HTML page for OAuth completions.
Response htmlPage(String title, String message, {bool ok = true}) => Response.ok(
      '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>$title</title><style>body{font-family:system-ui,sans-serif;background:#F7F4EE;color:#1E1C24;display:grid;place-items:center;height:100vh;margin:0}'
      'main{background:#fff;padding:40px 48px;border-radius:28px;box-shadow:0 8px 24px rgba(30,28,36,.12);max-width:420px;text-align:center}'
      'h1{font-size:28px;margin:0 0 12px}p{color:#5E5A66;line-height:1.5}</style></head>'
      '<body><main><div style="font-size:56px">${ok ? '✅' : '⚠️'}</div><h1>${const HtmlEscape().convert(title)}</h1>'
      '<p>${const HtmlEscape().convert(message)}</p></main></body></html>',
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
