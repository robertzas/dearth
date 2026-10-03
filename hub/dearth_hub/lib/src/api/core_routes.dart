import 'dart:convert';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../blobs.dart';
import '../connections.dart';
import 'context.dart';
import 'http_utils.dart';

/// Health, pairing, sync snapshot, blobs, image proxy and geocoding.
void mountCoreRoutes(Router r, HubContext ctx) {
  r.get('/api/health', (Request req) async => jsonOk({
        'ok': true,
        'version': hubVersion,
        'schema': kSchemaMajor,
        'uptimeS': (DateTime.now().millisecondsSinceEpoch - ctx.startedMs) ~/ 1000,
        'fake': ctx.config.fakeProviders,
        'publicUrl': ctx.config.publicUrl,
      }));

  // ── Pairing (SPEC §9.2) ──────────────────────────────────────────────────
  r.post('/api/pair/start', (Request req) async {
    final b = await readJson(req);
    final (id, code, secret) = await ctx.auth.startPairing(
      name: (b['name'] as String? ?? 'Display').trim(),
      platform: b['platform'] as String?,
      model: b['model'] as String?,
      role: b['role'] as String?,
    );
    final base = ctx.config.publicUrl ?? 'http://${req.requestedUri.authority}';
    return jsonOk({'pairingId': id, 'code': code, 'secret': secret, 'approveUrl': '$base/#/pair/$code', 'expiresInS': 900});
  });

  r.post('/api/pair/status', (Request req) async {
    final b = await readJson(req);
    final status = await ctx.auth.pairingStatus(b['pairingId'] as String? ?? '', b['secret'] as String? ?? '');
    return jsonOk(status.toJson());
  });

  r.post('/api/pair/claim', (Request req) async {
    final b = await readJson(req);
    final status = await ctx.auth.claim(
      (b['code'] as String? ?? '').trim(),
      platform: b['platform'] as String?,
      model: b['model'] as String?,
      name: b['name'] as String?,
    );
    if (status.status != 'approved') throw HttpError(404, 'invalid_code', 'That code is unknown, used or expired');
    return jsonOk(status.toJson());
  });

  // ── Sync bootstrap (SPEC §8.4.6) ─────────────────────────────────────────
  r.get('/api/sync/snapshot', (Request req) async {
    final device = await requireDevice(req, ctx.auth);
    final snap = await ctx.kernel.snapshot(device.role);
    final body = utf8.encode(jsonEncode(snap));
    final gz = (req.headers['accept-encoding'] ?? '').contains('gzip');
    return Response.ok(
      gz ? gzip.encode(body) : body,
      headers: {
        'content-type': 'application/json',
        'cache-control': 'no-store',
        if (gz) 'content-encoding': 'gzip',
      },
    );
  });

  // ── Blobs (SPEC §8.4.7) ──────────────────────────────────────────────────
  r.post('/api/blobs', (Request req) async {
    await requireDevice(req, ctx.auth);
    final bytes = <int>[];
    await for (final chunk in req.read()) {
      bytes.addAll(chunk);
      if (bytes.length > BlobStore.maxUploadBytes) throw HttpError(413, 'too_large');
    }
    if (bytes.isEmpty) throw HttpError(400, 'empty');
    final mime = req.headers['content-type']?.split(';').first.trim() ?? 'application/octet-stream';
    final normalize = req.url.queryParameters['normalize'] == '1' && mime.startsWith('image/');
    final entry = normalize ? await ctx.blobs.putImage(bytes) : await ctx.blobs.put(bytes, mime: mime);
    return jsonOk({'sha': entry.sha, 'mime': entry.mime, 'bytes': entry.bytes, 'width': entry.width, 'height': entry.height});
  });

  r.get('/api/blobs/<sha|[a-f0-9]{64}>', (Request req, String sha) async {
    final q = req.url.queryParameters;
    final entry = await ctx.blobs.entry(sha);
    if (entry == null) return jsonError(404, 'not_found');
    final file = await ctx.blobs.variant(
      sha,
      width: int.tryParse(q['w'] ?? ''),
      height: int.tryParse(q['h'] ?? ''),
      cover: q['fit'] == 'cover',
      blur: q['blur'] == '1',
    );
    if (file == null) return jsonError(404, 'not_found');
    final isVariant = file.path != ctx.blobs.fileFor(sha).path;
    return Response.ok(file.openRead(), headers: {
      'content-type': isVariant ? 'image/jpeg' : entry.mime,
      'cache-control': 'public, max-age=31536000, immutable',
      'content-length': '${file.lengthSync()}',
    });
  });

  // ── Image proxy (cached by origin URL) ───────────────────────────────────
  r.get('/api/img', (Request req) async {
    await requireDevice(req, ctx.auth);
    final q = req.url.queryParameters;
    final url = Uri.tryParse(q['u'] ?? '');
    if (url == null || !(url.isScheme('https') || url.isScheme('http'))) throw HttpError(400, 'bad_url');
    final entry = await ctx.blobs.fetchRemoteImage(ctx.fetcher, url);
    if (entry == null) return jsonError(404, 'not_found');
    final file = await ctx.blobs.variant(entry.sha, width: int.tryParse(q['w'] ?? ''), height: int.tryParse(q['h'] ?? ''), cover: q['fit'] == 'cover');
    return Response.ok(file!.openRead(), headers: {
      'content-type': 'image/jpeg',
      'cache-control': 'private, max-age=604800',
      'x-blob-sha': entry.sha,
    });
  });

  // ── Geocoding for household setup ────────────────────────────────────────
  r.get('/api/geo/search', (Request req) async {
    await requireDevice(req, ctx.auth);
    final q = (req.url.queryParameters['q'] ?? '').trim();
    if (q.isEmpty) return jsonOk(<Object>[]);
    if (ctx.config.fakeProviders) {
      return jsonOk([
        {'lat': 39.71, 'lon': -104.70, 'label': 'Aurora, CO', 'timezone': 'America/Denver', 'postalCode': '80018', 'countryCode': 'US'},
      ]);
    }
    final places = <Place>[];
    if (RegExp(r'^\d{5}(-\d{4})?$').hasMatch(q)) {
      final p = await lookupPostalCode(ctx.fetcher, q.substring(0, 5));
      if (p != null) places.add(p);
    }
    final om = OpenMeteo(ctx.fetcher);
    if (places.isEmpty) places.addAll(await om.searchPlaces(q));
    final withZones = <Place>[
      for (final p in places)
        p.timezone != null
            ? p
            : Place(lat: p.lat, lon: p.lon, label: p.label, postalCode: p.postalCode, countryCode: p.countryCode, timezone: await om.timezoneFor(p.lat, p.lon).catchError((Object _) => null)),
    ];
    places
      ..clear()
      ..addAll(withZones);
    return jsonOk([
      for (final p in places)
        {'lat': p.lat, 'lon': p.lon, 'label': p.label, 'timezone': p.timezone, 'postalCode': p.postalCode, 'countryCode': p.countryCode},
    ]);
  });
}
