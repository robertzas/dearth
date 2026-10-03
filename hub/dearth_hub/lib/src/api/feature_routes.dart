import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'context.dart';
import 'http_utils.dart';

/// Recipes and music (device-authenticated).
void mountFeatureRoutes(Router r, HubContext ctx) {
  List<String> csv(String? v) => (v ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  r.get('/api/recipes/search', (Request req) async {
    await requireDevice(req, ctx.auth);
    final q = req.url.queryParameters;
    final results = await ctx.recipes.search(RecipeQuery(
      text: q['q'],
      cuisine: q['cuisine'],
      category: q['category'],
      diet: q['diet'],
      maxMinutes: int.tryParse(q['maxMinutes'] ?? ''),
      includeIngredients: csv(q['include']),
      excludeIngredients: csv(q['exclude']),
      limit: (int.tryParse(q['limit'] ?? '') ?? 24).clamp(1, 48),
    ));
    return jsonOk([for (final x in results) x.toJson()]);
  });

  r.get('/api/recipes/discover/<feed>', (Request req, String feed) async {
    await requireDevice(req, ctx.auth);
    final q = req.url.queryParameters;
    final results = await ctx.recipes.discover(feed, arg: q['arg'], limit: (int.tryParse(q['limit'] ?? '') ?? 12).clamp(1, 36));
    return jsonOk([for (final x in results) x.toJson()]);
  });

  r.get('/api/recipes/cuisines', (Request req) async {
    await requireDevice(req, ctx.auth);
    return jsonOk(await ctx.recipes.cuisines());
  });

  r.post('/api/recipes/import', (Request req) async {
    await requireDevice(req, ctx.auth);
    final b = await readJson(req);
    final url = (b['url'] as String? ?? '').trim();
    if (url.isEmpty) throw HttpError(400, 'url_required');
    return jsonOk((await ctx.recipes.importUrl(url)).toJson());
  });

  r.post('/api/recipes/recommend', (Request req) async {
    await requireDevice(req, ctx.auth);
    final b = await readJson(req, maxBytes: 4 << 20);
    final planned = [for (final j in (b['recipes'] as List? ?? const [])) if (j is Map<String, Object?>) RecipeData.fromJson(j)];
    final excluded = {for (final e in (b['excluded'] as List? ?? const [])) '$e'};
    final ratings = {for (final e in (b['ratings'] as Map? ?? const {}).entries) '${e.key}': (e.value as num).toDouble()};
    final ranked = await ctx.recipes.recommend(planned, excluded: excluded, ratings: ratings, limit: (b['limit'] as num?)?.toInt() ?? 12);
    return jsonOk([
      for (final s in ranked) {'recipe': s.recipe.toJson(), 'score': s.score, 'matched': s.matched, 'added': s.added, 'why': s.explanation},
    ]);
  });

  // ── Music (SPEC §13.7) ───────────────────────────────────────────────────
  r.post('/api/music/resolve', (Request req) async {
    await requireDevice(req, ctx.auth);
    final b = await readJson(req);
    final input = (b['url'] as String? ?? '').trim();
    final yt = parseYouTubeId(input);
    if (yt != null) {
      if (ctx.config.fakeProviders) {
        return jsonOk({'source': 'youtube', 'ref': yt, 'title': 'YouTube video $yt', 'artUrl': 'https://i.ytimg.com/vi/$yt/hqdefault.jpg', 'embeddable': true});
      }
      try {
        final info = await YouTubeOEmbed(ctx.fetcher).resolve(yt);
        return jsonOk({'source': 'youtube', 'ref': yt, 'title': info.title, 'artist': info.artist, 'artUrl': info.artUrl, 'embeddable': true});
      } on ProviderException catch (e) {
        if (e.status == 401 || e.status == 403 || e.status == 404) {
          return jsonOk({'source': 'youtube', 'ref': yt, 'title': 'Video $yt', 'embeddable': false, 'message': 'This video cannot be played inside other apps.'});
        }
        rethrow;
      }
    }
    final sp = parseSpotifyUri(input);
    if (sp != null) {
      final token = await ctx.integrations.spotifyAccessToken();
      if (token == null) return jsonOk({'source': 'spotify', 'ref': sp, 'title': sp.split(':')[1], 'connected': false});
      final info = await SpotifyApi(ctx.fetcher, () async => token).describe(sp);
      return jsonOk({'source': 'spotify', 'ref': sp, 'title': info.title, 'artist': info.artist, 'artUrl': info.artUrl, 'connected': true});
    }
    throw HttpError(400, 'unsupported_link', 'Paste a YouTube, YouTube Music or Spotify link');
  });

  Future<SpotifyApi> spotify() async {
    final token = await ctx.integrations.spotifyAccessToken();
    if (token == null) throw HttpError(424, 'spotify_not_connected', 'Connect Spotify in Settings → Integrations');
    return SpotifyApi(ctx.fetcher, () async => token);
  }

  r.get('/api/music/spotify/devices', (Request req) async {
    await requireDevice(req, ctx.auth);
    final devices = await (await spotify()).devices();
    return jsonOk([for (final d in devices) {'id': d.id, 'name': d.name, 'type': d.type, 'active': d.active, 'volume': d.volume}]);
  });

  r.post('/api/music/spotify/play', (Request req) async {
    await requireDevice(req, ctx.auth);
    final b = await readJson(req);
    await (await spotify()).play(b['uri'] as String? ?? '', deviceId: b['deviceId'] as String?);
    return jsonOk({'ok': true});
  });

  r.post('/api/music/spotify/pause', (Request req) async {
    await requireDevice(req, ctx.auth);
    final b = await readJson(req);
    await (await spotify()).pause(deviceId: b['deviceId'] as String?);
    return jsonOk({'ok': true});
  });
}
