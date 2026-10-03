import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';

import 'config.dart';
import 'kernel.dart';
import 'storage.dart';

/// Secret ids in the vault (SPEC §9.5).
abstract final class SecretIds {
  static const wunderground = 'wu';
  static const spoonacular = 'spoonacular';
  static const themealdb = 'themealdb';
  static const googleClient = 'google:client';
  static const googleAccountPrefix = 'google:account:';
  static const spotifyClient = 'spotify:client';
  static const spotifyAccount = 'spotify:account';
  static const immichPrefix = 'immich:';
}

/// Integration configuration, provider construction and health reporting.
class Integrations {
  Integrations({required this.kernel, required this.vault, required this.config, required this.fetcher});

  final HubKernel kernel;
  final SecretVault vault;
  final HubConfig config;
  final Fetcher fetcher;
  final Map<String, Map<String, Object?>> _status = {};

  DearthDb get db => kernel.db;

  Future<Household?> household() => (db.select(db.households)..where((t) => t.id.equals(Ids.household))).getSingleOrNull();

  Future<Map<String, Object?>> setting(String key, {String scope = 'household'}) async {
    final row = await (db.select(db.settings)..where((t) => t.id.equals(Ids.setting(scope, key)))).getSingleOrNull();
    if (row == null) return const {};
    final v = jsonDecode(row.value);
    return v is Map<String, Object?> ? v : const {};
  }

  Future<void> putSetting(String key, Object? value, {String scope = 'household'}) =>
      kernel.upsert('settings', Ids.setting(scope, key), {'scope': scope, 'key': key, 'value': value});

  Future<String?> secretField(String id, String field) async => (await vault.getJson(id))?[field] as String?;

  // ─────────────────────────────── Health ──────────────────────────────────

  /// Records integration health and publishes it as a synced setting so every
  /// device's Settings → Integrations page can show it (FR-ADM-05).
  Future<void> report(String name, {required bool ok, String? message, Map<String, Object?> extra = const {}}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _status[name] ?? const {};
    _status[name] = {
      'ok': ok,
      'message': message,
      'lastRunMs': now,
      'lastOkMs': ok ? now : prev['lastOkMs'],
      ...extra,
    };
    await putSetting('integrations.status', _status);
  }

  Map<String, Map<String, Object?>> get status => Map.unmodifiable(_status);

  // ─────────────────────────────── Weather ─────────────────────────────────

  Future<WeatherConfig?> weatherConfig() async {
    final h = await household();
    if (h == null || h.lat == null || h.lon == null) return null;
    final station = await setting(SettingKeys.weatherStation);
    return WeatherConfig(
      lat: h.lat!,
      lon: h.lon!,
      timezone: h.timezone,
      label: h.locationLabel,
      countryCode: h.countryCode,
      wuApiKey: await secretField(SecretIds.wunderground, 'apiKey'),
      stationId: (station['stationId'] as String?)?.trim(),
      useWuForecast: station['useWuForecast'] as bool? ?? true,
    );
  }

  WeatherSource weatherSource() => config.fakeProviders ? FakeWeather() : WeatherService(fetcher, contact: config.contact);

  // ─────────────────────────────── Recipes ─────────────────────────────────

  Future<List<RecipeProvider>> recipeProviders() async {
    if (config.fakeProviders) return [CatalogRecipes()];
    final spoon = await secretField(SecretIds.spoonacular, 'apiKey');
    final meal = await secretField(SecretIds.themealdb, 'apiKey');
    return [
      if (spoon != null && spoon.isNotEmpty) Spoonacular(fetcher, spoon, budget: _spoonBudget),
      TheMealDb(fetcher, apiKey: meal ?? '1'),
      CatalogRecipes(),
    ];
  }

  final PointBudget _spoonBudget = PointBudget();
  double get spoonacularPointsUsed => _spoonBudget.used;

  // ─────────────────────────────── Google ──────────────────────────────────

  Future<GoogleOAuth?> googleOAuth() async {
    final c = await vault.getJson(SecretIds.googleClient);
    final id = c?['clientId'] as String?;
    final secret = c?['clientSecret'] as String?;
    if (id == null || secret == null || id.isEmpty) return null;
    return GoogleOAuth(fetcher, clientId: id, clientSecret: secret);
  }

  Future<List<String>> googleAccounts() async =>
      [for (final id in await vault.ids(prefix: SecretIds.googleAccountPrefix)) id.substring(SecretIds.googleAccountPrefix.length)];

  /// A fresh access token for a Google account, refreshing and persisting as
  /// needed. Throws [ProviderException] with `isAuth` when reconnect is needed.
  Future<String> googleAccessToken(String accountId) async {
    final secretId = '${SecretIds.googleAccountPrefix}$accountId';
    final stored = await vault.getJson(secretId);
    if (stored == null) throw ProviderException('google', 'Account $accountId not connected', status: 401);
    var tokens = OAuthTokens.fromJson(stored.obj('tokens'));
    if (tokens.expiresWithin(const Duration(minutes: 2))) {
      final oauth = await googleOAuth();
      if (oauth == null || tokens.refreshToken == null) throw ProviderException('google', 'Google client not configured', status: 401);
      tokens = await oauth.refresh(tokens.refreshToken!);
      await vault.putJson(secretId, {...stored, 'tokens': tokens.toJson()});
    }
    return tokens.accessToken;
  }

  // ─────────────────────────────── Spotify ─────────────────────────────────

  Future<String?> spotifyClientId() => secretField(SecretIds.spotifyClient, 'clientId');

  Future<String?> spotifyAccessToken() async {
    final stored = await vault.getJson(SecretIds.spotifyAccount);
    if (stored == null) return null;
    var tokens = OAuthTokens.fromJson(stored.obj('tokens'));
    if (tokens.expiresWithin(const Duration(minutes: 2))) {
      final clientId = await spotifyClientId();
      if (clientId == null || tokens.refreshToken == null) return null;
      tokens = await SpotifyAuth(fetcher, clientId: clientId).refresh(tokens.refreshToken!);
      await vault.putJson(SecretIds.spotifyAccount, {...stored, 'tokens': tokens.toJson()});
    }
    return tokens.accessToken;
  }

  /// OAuth redirect base: the public HTTPS origin when configured.
  String? get publicOrigin => config.publicUrl;
}
