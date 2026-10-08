import 'dart:async';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../connections.dart';
import '../integrations.dart';
import '../jobs/photos_job.dart';
import '../storage.dart';
import 'context.dart';
import 'http_utils.dart';

/// Admin, integration settings, OAuth, photo sources and webhooks.
void mountAdminRoutes(Router r, HubContext ctx) {
  // ── Status & devices (FR-ADM-01) ─────────────────────────────────────────
  r.get('/api/admin/status', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final devices = await ctx.auth.devices();
    final db = ctx.kernel.db;
    final jobs = await db.select(db.jobStates).get();
    final dbFile = File(ctx.config.dbPath);
    return jsonOk({
      'hub': {
        'version': hubVersion,
        'uptimeS': (DateTime.now().millisecondsSinceEpoch - ctx.startedMs) ~/ 1000,
        'vips': await ctx.blobs.vipsAvailable,
        'dbBytes': dbFile.existsSync() ? dbFile.lengthSync() : 0,
        'publicUrl': ctx.config.publicUrl,
        'fakeProviders': ctx.config.fakeProviders,
        'seq': await ctx.kernel.maxSeq(),
      },
      'devices': [
        for (final d in devices)
          {
            'id': d.deviceId,
            'name': d.name,
            'role': d.role,
            'admin': d.admin,
            'online': ctx.connections.isOnline(d.deviceId),
            'lastSeenMs': d.lastSeenMs,
            'telemetry': ctx.connections.telemetry[d.deviceId],
          },
      ],
      'pendingPairings': [
        for (final p in await ctx.auth.pendingPairings()) {'code': p.code, 'name': p.deviceName, 'platform': p.platform, 'requestedMs': p.requestedMs},
      ],
      'integrations': ctx.integrations.status,
      'jobs': [for (final j in jobs) {'id': j.id, 'lastRunMs': j.lastRunMs, 'lastOkMs': j.lastOkMs, 'lastError': j.lastError}],
      'spoonacularPointsUsed': ctx.integrations.spoonacularPointsUsed,
    });
  });

  r.post('/api/admin/pair/approve', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final ok = await ctx.auth.approve(
      b['code'] as String? ?? '',
      role: b['role'] as String?,
      admin: b['admin'] as bool?,
      name: b['name'] as String?,
      orientation: b['orientation'] as String?,
    );
    if (!ok) throw HttpError(404, 'invalid_code', 'No pending pairing with that code');
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/enroll', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final code = await ctx.auth.enroll(
      name: b['name'] as String? ?? 'Display',
      role: DeviceRole.all.contains(b['role']) ? b['role']! as String : DeviceRole.kitchen,
      admin: b['admin'] as bool? ?? false,
      orientation: b['orientation'] as String?,
    );
    return jsonOk({'code': code, 'expiresInS': 1800});
  });

  r.post('/api/admin/devices/<id>', (Request req, String id) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    await ctx.auth.setDeviceRole(id, role: b['role'] as String?, admin: b['admin'] as bool?);
    return jsonOk({'ok': true});
  });

  r.delete('/api/admin/devices/<id>', (Request req, String id) async {
    await requireAdmin(req, ctx.auth);
    await ctx.auth.revoke(id);
    await ctx.connections.disconnect(id);
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/devices/<id>/command', (Request req, String id) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final result = await ctx.connections.command(id, b['command'] as String? ?? 'ping', args: Map<String, Object?>.from(b['args'] as Map? ?? const {}));
    if (result == null) throw HttpError(504, 'device_unreachable', 'The device is offline or did not answer');
    return jsonOk({'ok': result.ok, 'data': result.data});
  });

  r.post('/api/admin/jobs/<id>/run', (Request req, String id) async {
    await requireAdmin(req, ctx.auth);
    unawaited(ctx.scheduler.runAndWait(id));
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/backup', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final f = await backupDatabase(ctx.kernel.db, ctx.config.backupDir, reason: 'manual', keep: 10);
    if (f == null) throw HttpError(500, 'backup_failed');
    return jsonOk({'file': f.path, 'bytes': f.lengthSync()});
  });

  r.get('/api/admin/export', (Request req) async {
    await requireAdmin(req, ctx.auth);
    return jsonOk(await ctx.kernel.snapshot(DeviceRole.personal));
  });

  r.post('/api/admin/demo-seed', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final tz = (await ctx.integrations.household())?.timezone ?? 'America/Denver';
    final ops = await demoSeedOps(ctx.kernel.mutator, HouseholdTime.named(tz == 'UTC' ? 'America/Denver' : tz));
    await ctx.kernel.write(ops);
    return jsonOk({'ok': true, 'ops': ops.length});
  });

  // ── Integration settings (secrets never leave the Hub) ───────────────────
  r.get('/api/admin/integrations', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final station = await ctx.integrations.setting(SettingKeys.weatherStation);
    Future<bool> has(String id, String field) async => (await ctx.integrations.secretField(id, field))?.isNotEmpty ?? false;
    return jsonOk({
      'weather': {'hasKey': await has(SecretIds.wunderground, 'apiKey'), ...station},
      'spoonacular': {'hasKey': await has(SecretIds.spoonacular, 'apiKey')},
      'themealdb': {'hasKey': await has(SecretIds.themealdb, 'apiKey')},
      // Settings → Recipes (FR-RCP-01, FR-RCP-13): keys are never sent back.
      'recipes': await () async {
        final off = await ctx.integrations.recipeSourcesOff();
        return [
          for (final source in kRecipeSources)
            {
              'id': source.id,
              'name': source.name,
              'note': source.note,
              'needsKey': source.needsKey,
              'hasKey': !source.needsKey || await has(source.id, 'apiKey'),
              'on': !off.contains(source.id),
              if (ctx.integrations.recipeQuotas[source.id] case final q?) 'quota': {'used': q.used, 'allowed': q.allowed, 'limit': q.limit},
            },
        ];
      }(),
      'google': {
        'hasClient': await has(SecretIds.googleClient, 'clientId'),
        'accounts': [
          for (final id in await ctx.integrations.googleAccounts())
            if (await ctx.vault.getJson('${SecretIds.googleAccountPrefix}$id') case final stored?)
              {
                'id': id,
                'email': stored['email'],
                // Whether the account allowed Google Tasks (list sync).
                'tasks': '${(stored['tokens'] as Map?)?['scope'] ?? ''}'.contains(GoogleTasksApi.scope),
              },
        ],
        'redirectUri': _googleRedirect(ctx),
      },
      'spotify': {
        'hasClient': (await ctx.integrations.spotifyClientId()) != null,
        'connected': (await ctx.vault.getJson(SecretIds.spotifyAccount)) != null,
        'redirectUri': _spotifyRedirect(ctx),
      },
      'publicUrl': ctx.config.publicUrl,
    });
  });

  r.put('/api/admin/integrations/<name>', (Request req, String name) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    String? str(String k) => (b[k] as String?)?.trim();
    switch (name) {
      case 'weather':
        if (b.containsKey('apiKey')) {
          final key = str('apiKey');
          key == null || key.isEmpty ? await ctx.vault.remove(SecretIds.wunderground) : await ctx.vault.putJson(SecretIds.wunderground, {'apiKey': key});
        }
        await ctx.integrations.putSetting(SettingKeys.weatherStation, {
          'stationId': str('stationId') ?? '',
          'useWuForecast': b['useWuForecast'] as bool? ?? true,
        });
        ctx.scheduler.runNow('weather');
      case 'spoonacular' || 'themealdb':
        final key = str('apiKey');
        key == null || key.isEmpty ? await ctx.vault.remove(name) : await ctx.vault.putJson(name, {'apiKey': key});
        ctx.recipes.clearCache();
      case 'recipes':
        final source = kRecipeSources.where((s) => s.id == str('source')).firstOrNull;
        if (source == null) throw HttpError(400, 'unknown_source');
        if (b['on'] is bool) await ctx.integrations.setRecipeSource(source.id, on: b['on']! as bool);
        if (source.needsKey && b.containsKey('apiKey')) {
          final key = str('apiKey');
          key == null || key.isEmpty ? await ctx.vault.remove(source.id) : await ctx.vault.putJson(source.id, {'apiKey': key});
        }
        ctx.recipes.clearCache();
      case 'google':
        await ctx.vault.putJson(SecretIds.googleClient, {'clientId': str('clientId'), 'clientSecret': str('clientSecret')});
      case 'spotify':
        await ctx.vault.putJson(SecretIds.spotifyClient, {'clientId': str('clientId')});
      default:
        throw HttpError(404, 'unknown_integration');
    }
    return jsonOk({'ok': true});
  });

  r.get('/api/admin/weather/stations', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final key = await ctx.integrations.secretField(SecretIds.wunderground, 'apiKey');
    if (key == null) throw HttpError(424, 'wu_key_required', 'Add your Weather Underground API key first');
    final h = await ctx.integrations.household();
    if (h?.lat == null) throw HttpError(409, 'location_required', 'Set the household location first');
    final near = await WundergroundClient(ctx.fetcher, key).nearbyStations(h!.lat!, h.lon!);
    return jsonOk([for (final (id, name, km) in near) {'id': id, 'name': name, 'distanceKm': km}]);
  });

  r.post('/api/admin/calendars/ics', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final url = (b['url'] as String? ?? '').trim();
    if (!RegExp(r'^(https?|webcal)://', caseSensitive: false).hasMatch(url)) throw HttpError(400, 'bad_url', 'Use an https:// or webcal:// link');
    final id = await ctx.kernel.create('calendar_sources', {
      'kind': 'ics',
      'name': (b['name'] as String?)?.trim().isNotEmpty ?? false ? b['name'] : 'Subscribed calendar',
      'url': url,
      'color': (b['color'] as num?)?.toInt() ?? 0xFF26A9A0,
      'writable': false,
      'default_profile_ids': b['profileIds'] ?? const [],
      'enabled': true,
    });
    ctx.scheduler.runNow('ics');
    return jsonOk({'id': id});
  });

  // ── Photo sources (SPEC §13.5) ───────────────────────────────────────────
  r.post('/api/admin/photos/sources', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final kind = b['kind'] as String? ?? '';
    final cfg = Map<String, Object?>.from(b['config'] as Map? ?? const {});
    switch (kind) {
      case 'amazon':
        if (AmazonShareLink.parse(cfg['shareUrl'] as String? ?? '') == null) throw HttpError(400, 'bad_link', 'Paste an Amazon Photos share link');
      case 'folder':
        if ((cfg['path'] as String? ?? '').isEmpty) throw HttpError(400, 'path_required');
      case 'immich':
        if ((cfg['url'] as String? ?? '').isEmpty || (b['apiKey'] as String? ?? '').isEmpty) throw HttpError(400, 'immich_required', 'URL and API key are required');
      case 'google':
        if ((await ctx.integrations.googleAccounts()).isEmpty) throw HttpError(424, 'google_required', 'Connect a Google account first');
      default:
        throw HttpError(400, 'unknown_kind');
    }
    final key = photoSourceKey(kind, cfg);
    if (key != null) {
      final db = ctx.kernel.db;
      final others = await (db.select(db.photoSources)..where((t) => t.kind.equals(kind) & t.deleted.equals(false))).get();
      if (others.any((o) => photoSourceKey(o.kind, decodeJsonMap(o.config)) == key)) throw HttpError(409, 'duplicate_source', 'That album is already one of your photo sources');
    }
    final id = await ctx.kernel.create('photo_sources', {'kind': kind, 'name': b['name'] ?? _defaultName(kind), 'config': cfg, 'enabled': true});
    if (kind == 'immich') await ctx.vault.putJson('${SecretIds.immichPrefix}$id', {'apiKey': b['apiKey']});
    if (kind == 'google') return jsonOk({'id': id, ...await _newPickerSession(ctx, id)});
    ctx.scheduler.runNow('photos');
    return jsonOk({'id': id});
  });

  r.delete('/api/admin/photos/sources/<id>', (Request req, String id) async {
    await requireAdmin(req, ctx.auth);
    await removePhotoSource(ctx.kernel, id);
    await ctx.vault.remove('${SecretIds.immichPrefix}$id');
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/photos/sources/<id>/pick', (Request req, String id) async {
    await requireAdmin(req, ctx.auth);
    return jsonOk(await _newPickerSession(ctx, id));
  });

  r.post('/api/admin/photos/refresh', (Request req) async {
    await requireAdmin(req, ctx.auth);
    ctx.scheduler.runNow('photos');
    return jsonOk({'ok': true});
  });

  // ── OAuth (SPEC §13.2, §13.7) ────────────────────────────────────────────
  r.get('/api/admin/oauth/google/start', (Request req) async {
    await requireAdmin(req, ctx.auth);
    return jsonOk(await _startGoogle(ctx, req.url.queryParameters['purpose'] ?? 'calendar'));
  });

  // FR-CAL-04: the shared "Family" Google calendar. Made at once when the
  // account already allowed it, else after one more Google consent (the
  // reply carries its URL, like /oauth/google/start).
  r.post('/api/admin/calendars/google/family', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final accounts = await ctx.integrations.googleAccounts();
    final account = b['account'] is String && accounts.contains(b['account']) ? b['account']! as String : accounts.firstOrNull;
    if (account == null) throw HttpError(424, 'google_required', 'Connect a Google account first');
    final share = [for (final e in b['share'] is List ? b['share']! as List : const []) if (e is String && e.contains('@')) e.trim()];
    final move = b['move'] == true;
    final stored = await ctx.vault.getJson('${SecretIds.googleAccountPrefix}$account');
    final granted = '${(stored?['tokens'] as Map?)?['scope'] ?? ''}';
    if (granted.contains(GoogleOAuth.appCalendarsScope) && (share.isEmpty || granted.contains(GoogleOAuth.sharingScope))) {
      try {
        return jsonOk({'created': true, ...await ctx.google.createFamilyCalendar(account: account, share: share, move: move)});
      } on ProviderException catch (e) {
        if (!e.isAuth) throw HttpError(502, 'google_failed', e.message);
        // A revoked permission: ask again.
      }
    }
    return jsonOk({
      'created': false,
      ...await _startGoogle(ctx, 'family', loginHint: account, extra: {'share': share, 'move': move}, sharing: share.isNotEmpty),
    });
  });

  r.post('/api/admin/oauth/google/complete', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final uri = Uri.tryParse(b['url'] as String? ?? '');
    if (uri == null) throw HttpError(400, 'bad_url');
    return jsonOk(await _finishGoogle(ctx, uri.queryParameters['code'], uri.queryParameters['state']));
  });

  r.get('/api/oauth/google/callback', (Request req) async {
    final q = req.url.queryParameters;
    if (q['error'] != null) return htmlPage('Google sign-in cancelled', q['error']!, ok: false);
    try {
      final res = await _finishGoogle(ctx, q['code'], q['state']);
      if (res['family'] case {'shared': final List<Object?> shared}) {
        final who = shared.isEmpty ? '' : ' and shared it with ${shared.join(' and ')}';
        return htmlPage('Family calendar made', 'Dearth made a “Family” calendar in ${res['email']}’s Google Calendar$who. Events added on the wall land there. You can close this tab.');
      }
      return htmlPage('Google connected', 'Signed in as ${res['email']}. You can close this tab — your calendars and lists sync with Dearth in a moment.');
    } on HttpError catch (e) {
      return htmlPage('Google connection failed', e.message ?? e.code, ok: false);
    }
  });

  r.delete('/api/admin/google/<account>', (Request req, String account) async {
    await requireAdmin(req, ctx.auth);
    await ctx.vault.remove('${SecretIds.googleAccountPrefix}$account');
    final db = ctx.kernel.db;
    final sources = await (db.select(db.calendarSources)..where((t) => t.accountId.equals(account))).get();
    for (final s in sources) {
      await ctx.kernel.upsert('calendar_sources', s.id, {'enabled': false, 'status': 'disconnected'});
    }
    return jsonOk({'ok': true});
  });

  r.get('/api/admin/oauth/spotify/start', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final clientId = await ctx.integrations.spotifyClientId();
    if (clientId == null) throw HttpError(424, 'spotify_client_required', 'Add your Spotify client ID first');
    final state = randomToken(bytes: 16);
    final verifier = pkceVerifier();
    final redirect = _spotifyRedirect(ctx);
    ctx.oauthStates[state] = {'provider': 'spotify', 'verifier': verifier, 'redirect': redirect, 'createdMs': DateTime.now().millisecondsSinceEpoch};
    final url = SpotifyAuth(ctx.fetcher, clientId: clientId).authorizationUrl(redirectUri: redirect, state: state, codeChallenge: pkceChallenge(verifier));
    return jsonOk({'url': url.toString(), 'mode': ctx.config.hasHttpsPublicUrl ? 'callback' : 'paste', 'redirectUri': redirect});
  });

  r.post('/api/admin/oauth/spotify/complete', (Request req) async {
    await requireAdmin(req, ctx.auth);
    final b = await readJson(req);
    final uri = Uri.tryParse(b['url'] as String? ?? '');
    if (uri == null) throw HttpError(400, 'bad_url');
    await _finishSpotify(ctx, uri.queryParameters['code'], uri.queryParameters['state']);
    return jsonOk({'ok': true});
  });

  r.get('/api/oauth/spotify/callback', (Request req) async {
    final q = req.url.queryParameters;
    try {
      await _finishSpotify(ctx, q['code'], q['state']);
      return htmlPage('Spotify connected', 'You can close this tab and add Spotify songs to the music box.');
    } on HttpError catch (e) {
      return htmlPage('Spotify connection failed', e.message ?? e.code, ok: false);
    }
  });

  // ── Webhooks ─────────────────────────────────────────────────────────────
  r.post('/api/webhooks/google/calendar', (Request req) async {
    final ok = await ctx.google.webhook(
      channelId: req.headers['x-goog-channel-id'] ?? '',
      token: req.headers['x-goog-channel-token'] ?? '',
    );
    return Response(ok ? 200 : 404);
  });
}

String _defaultName(String kind) => switch (kind) {
      'amazon' => 'Amazon Photos',
      'google' => 'Google Photos',
      'immich' => 'Immich',
      'folder' => 'Photo folder',
      _ => 'Photos',
    };

/// A Google consent URL for [purpose] (SPEC §13.2). [extra] rides along in
/// the OAuth state to the finish.
Future<Map<String, Object?>> _startGoogle(HubContext ctx, String purpose, {String? loginHint, Map<String, Object?> extra = const {}, bool sharing = false}) async {
  final oauth = await ctx.integrations.googleOAuth();
  if (oauth == null) throw HttpError(424, 'google_client_required', 'Add your Google OAuth client ID and secret first');
  final state = randomToken(bytes: 16);
  final verifier = pkceVerifier();
  final redirect = _googleRedirect(ctx);
  ctx.oauthStates[state] = {...extra, 'provider': 'google', 'verifier': verifier, 'purpose': purpose, 'redirect': redirect, 'createdMs': DateTime.now().millisecondsSinceEpoch};
  // Incremental consent: a purpose adds its scope to the calendar ones.
  final scopes = [
    ...GoogleOAuth.calendarScopes,
    if (purpose == 'photos') GoogleOAuth.photosPickerScope,
    if (purpose == 'tasks') GoogleTasksApi.scope,
    if (purpose == 'family') GoogleOAuth.appCalendarsScope,
    if (purpose == 'family' && sharing) GoogleOAuth.sharingScope,
  ];
  final url = oauth.authorizationUrl(redirectUri: redirect, state: state, scopes: scopes, codeChallenge: pkceChallenge(verifier), loginHint: loginHint);
  return {'url': url.toString(), 'mode': ctx.config.hasHttpsPublicUrl ? 'callback' : 'paste', 'redirectUri': redirect};
}

String _googleRedirect(HubContext ctx) =>
    ctx.config.hasHttpsPublicUrl ? '${ctx.config.publicUrl}/api/oauth/google/callback' : 'http://localhost/dearth-oauth';

String _spotifyRedirect(HubContext ctx) =>
    ctx.config.hasHttpsPublicUrl ? '${ctx.config.publicUrl}/api/oauth/spotify/callback' : 'http://127.0.0.1:8888/callback';

Map<String, Object?> _takeState(HubContext ctx, String? state, String provider) {
  ctx.oauthStates.removeWhere((_, v) => DateTime.now().millisecondsSinceEpoch - ((v['createdMs'] as int?) ?? 0) > 15 * 60000);
  final s = state == null ? null : ctx.oauthStates.remove(state);
  if (s == null || s['provider'] != provider) throw HttpError(400, 'bad_state', 'This sign-in link expired. Start again from Dearth.');
  return s;
}

Future<Map<String, Object?>> _finishGoogle(HubContext ctx, String? code, String? state) async {
  if (code == null) throw HttpError(400, 'code_missing');
  final s = _takeState(ctx, state, 'google');
  final oauth = await ctx.integrations.googleOAuth();
  if (oauth == null) throw HttpError(424, 'google_client_required');
  final tokens = await oauth.exchangeCode(code, redirectUri: s['redirect']! as String, codeVerifier: s['verifier'] as String?);
  if (tokens.refreshToken == null) throw HttpError(400, 'no_refresh_token', 'Google did not return offline access; remove Dearth from your Google account permissions and try again.');
  final info = await oauth.userInfo(tokens.accessToken);
  final accountId = (info['email'] as String?) ?? (info['sub'] as String? ?? newId());
  await ctx.vault.putJson('${SecretIds.googleAccountPrefix}$accountId', {'email': info['email'], 'tokens': tokens.toJson()});

  // Link calendars: primary on by default, others off until chosen.
  final api = GoogleCalendarApi(ctx.fetcher, () async => tokens.accessToken);
  final calendars = await api.calendarList();
  for (final c in calendars) {
    final id = stableId('gcal', [accountId, c.id]);
    final existing = await ctx.kernel.store.readRow('calendar_sources', id);
    await ctx.kernel.upsert('calendar_sources', id, {
      'kind': 'google',
      'account_id': accountId,
      'remote_id': c.id,
      'name': c.summary,
      'color': _hexColor(c.colorHex),
      'writable': c.writable,
      // Reconnecting (to allow Tasks, say) keeps the family's choices.
      if (existing == null) 'enabled': c.primary,
      if (existing == null) 'is_default': false,
      'deleted': false,
    });
  }
  Map<String, Object?>? family;
  if (s['purpose'] == 'family') {
    try {
      family = await ctx.google.createFamilyCalendar(
        account: accountId,
        share: [for (final e in s['share'] is List ? s['share']! as List : const []) if (e is String) e],
        move: s['move'] == true,
      );
    } on ProviderException catch (e) {
      throw HttpError(502, 'google_failed', 'Signed in, but Google wouldn’t make the Family calendar: ${e.message}');
    }
  }
  ctx.scheduler
    ..runNow('google-calendar')
    ..runNow('google-tasks');
  return {'ok': true, 'email': accountId, 'calendars': calendars.length, 'family': ?family};
}

Future<void> _finishSpotify(HubContext ctx, String? code, String? state) async {
  if (code == null) throw HttpError(400, 'code_missing');
  final s = _takeState(ctx, state, 'spotify');
  final clientId = await ctx.integrations.spotifyClientId();
  if (clientId == null) throw HttpError(424, 'spotify_client_required');
  final tokens = await SpotifyAuth(ctx.fetcher, clientId: clientId).exchangeCode(code, redirectUri: s['redirect']! as String, codeVerifier: s['verifier']! as String);
  await ctx.vault.putJson(SecretIds.spotifyAccount, {'tokens': tokens.toJson()});
}

Future<Map<String, Object?>> _newPickerSession(HubContext ctx, String sourceId) async {
  final account = (await ctx.integrations.googleAccounts()).firstOrNull;
  if (account == null) throw HttpError(424, 'google_required');
  final picker = GooglePhotosPicker(ctx.fetcher, () => ctx.integrations.googleAccessToken(account));
  final session = await picker.createSession();
  await ctx.jobs.write('gpicker:$sourceId', data: {'sessionId': session.id});
  // Poll for the picked items while the family picks on a phone.
  unawaited(() async {
    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(session.pollInterval);
      final s = await picker.getSession(session.id).catchError((Object _) => session);
      if (s.itemsSet) {
        await ctx.scheduler.runAndWait('photos');
        return;
      }
    }
  }());
  return {'pickerUri': '${session.pickerUri}', 'sessionId': session.id};
}

int _hexColor(String? hex) {
  final v = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  return v == null ? 0xFF3D9BE9 : 0xFF000000 | v;
}
