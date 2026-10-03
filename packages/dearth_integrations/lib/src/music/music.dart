import 'package:meta/meta.dart';

import '../calendar/oauth.dart';
import '../http/fetcher.dart';

/// Metadata for a curated music tile (SPEC §10.9).
@immutable
class TrackInfo {
  const TrackInfo({required this.source, required this.ref, required this.title, this.artist, this.artUrl});
  final String source;
  final String ref;
  final String title;
  final String? artist;
  final String? artUrl;
}

// ──────────────────────────────── YouTube ──────────────────────────────────

/// Extracts a video id from YouTube / YouTube Music URLs.
String? parseYouTubeId(String input) {
  final s = input.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(s)) return s;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  final host = uri.host.replaceFirst('www.', '').replaceFirst('m.', '');
  if (host == 'youtu.be') return _id(uri.pathSegments.firstOrNull);
  if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    if (uri.queryParameters['v'] != null) return _id(uri.queryParameters['v']);
    final segs = uri.pathSegments;
    for (final marker in const ['shorts', 'embed', 'live', 'v']) {
      final i = segs.indexOf(marker);
      if (i >= 0 && i + 1 < segs.length) return _id(segs[i + 1]);
    }
  }
  return null;
}

String? _id(String? v) => v != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(v) ? v : null;

/// YouTube oEmbed (no key). Throws [ProviderException] with 401/404 when the
/// video is private or embedding is disabled (FR-MUS-02).
class YouTubeOEmbed {
  YouTubeOEmbed(this.fetcher);
  final Fetcher fetcher;

  Future<TrackInfo> resolve(String videoId) async {
    final j = asObject(
      await fetcher.getJson('youtube', Uri.https('www.youtube.com', '/oembed', {'url': 'https://www.youtube.com/watch?v=$videoId', 'format': 'json'})),
      'youtube',
    );
    return TrackInfo(
      source: 'youtube',
      ref: videoId,
      title: j['title'] as String? ?? 'YouTube video',
      artist: j['author_name'] as String?,
      artUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
    );
  }
}

// ──────────────────────────────── Spotify ──────────────────────────────────

/// `spotify:track:ID` from open.spotify.com links or URIs.
String? parseSpotifyUri(String input) {
  final s = input.trim();
  if (RegExp(r'^spotify:(track|album|playlist|artist|episode|show):[A-Za-z0-9]+$').hasMatch(s)) return s;
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.host.endsWith('spotify.com')) return null;
  final segs = uri.pathSegments.where((p) => !p.startsWith('intl-')).toList();
  if (segs.length < 2) return null;
  const kinds = {'track', 'album', 'playlist', 'artist', 'episode', 'show'};
  return kinds.contains(segs[0]) ? 'spotify:${segs[0]}:${segs[1]}' : null;
}

@immutable
class SpotifyDevice {
  const SpotifyDevice({required this.id, required this.name, required this.type, required this.active, this.volume});
  final String id;
  final String name;
  final String type;
  final bool active;
  final int? volume;
}

/// Spotify Authorization Code + PKCE (SPEC §13.7).
class SpotifyAuth {
  SpotifyAuth(this.fetcher, {required this.clientId});
  final Fetcher fetcher;
  final String clientId;
  static const scopes = ['user-read-playback-state', 'user-modify-playback-state', 'playlist-read-private', 'user-library-read'];

  Uri authorizationUrl({required String redirectUri, required String state, required String codeChallenge}) =>
      Uri.https('accounts.spotify.com', '/authorize', {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': codeChallenge,
        'scope': scopes.join(' '),
        'state': state,
      });

  Future<OAuthTokens> exchangeCode(String code, {required String redirectUri, required String codeVerifier}) async {
    final j = await fetcher.postJson('spotify', Uri.parse('https://accounts.spotify.com/api/token'), body: {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': codeVerifier,
    });
    return OAuthTokens.fromResponse(asObject(j, 'spotify'));
  }

  Future<OAuthTokens> refresh(String refreshToken) async {
    final j = await fetcher.postJson('spotify', Uri.parse('https://accounts.spotify.com/api/token'), body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
    });
    return OAuthTokens.fromResponse(asObject(j, 'spotify'), previousRefreshToken: refreshToken);
  }
}

/// Spotify Web API playback control (Premium required for playback).
class SpotifyApi {
  SpotifyApi(this.fetcher, this.token);
  final Fetcher fetcher;
  final Future<String> Function() token;
  static final _base = Uri.parse('https://api.spotify.com/v1');

  Future<Map<String, String>> _h() async => {'Authorization': 'Bearer ${await token()}'};

  Future<List<SpotifyDevice>> devices() async {
    final j = asObject(await fetcher.getJson('spotify', Uri.parse('$_base/me/player/devices'), headers: await _h()), 'spotify');
    return [
      for (final d in asArray(j['devices']))
        if (d is Map<String, Object?>)
          SpotifyDevice(
            id: d['id'] as String? ?? '',
            name: d['name'] as String? ?? 'Device',
            type: d['type'] as String? ?? 'Speaker',
            active: d['is_active'] as bool? ?? false,
            volume: (d['volume_percent'] as num?)?.toInt(),
          ),
    ];
  }

  /// Plays a track/album/playlist URI on [deviceId].
  Future<void> play(String spotifyUri, {String? deviceId}) async {
    final isTrack = spotifyUri.startsWith('spotify:track:') || spotifyUri.startsWith('spotify:episode:');
    await fetcher.send(
      'spotify',
      'PUT',
      Uri.parse('$_base/me/player/play').replace(queryParameters: {'device_id': ?deviceId}),
      headers: await _h(),
      body: isTrack ? {'uris': [spotifyUri]} : {'context_uri': spotifyUri},
      retry: false,
    );
  }

  Future<void> pause({String? deviceId}) async {
    await fetcher.send('spotify', 'PUT', Uri.parse('$_base/me/player/pause').replace(queryParameters: {'device_id': ?deviceId}), headers: await _h(), retry: false);
  }

  /// Title/artist/art for a tile.
  Future<TrackInfo> describe(String spotifyUri) async {
    final parts = spotifyUri.split(':');
    final kind = parts[1];
    final id = parts[2];
    final j = asObject(await fetcher.getJson('spotify', Uri.parse('$_base/${kind}s/$id'), headers: await _h()), 'spotify');
    final images = asArray(j['images'] ?? (j['album'] is Map ? (j['album']! as Map)['images'] : null));
    final artists = asArray(j['artists']);
    final owner = j['owner'];
    return TrackInfo(
      source: 'spotify',
      ref: spotifyUri,
      title: j['name'] as String? ?? 'Spotify',
      artist: artists.isNotEmpty ? (artists.first! as Map)['name'] as String? : (owner is Map ? owner['display_name'] as String? : null),
      artUrl: images.isNotEmpty ? (images.first! as Map)['url'] as String? : null,
    );
  }
}
