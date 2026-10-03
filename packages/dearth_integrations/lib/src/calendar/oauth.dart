import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../http/fetcher.dart';

/// OAuth 2.0 tokens as stored (encrypted) by the Hub.
@immutable
class OAuthTokens {
  const OAuthTokens({required this.accessToken, required this.expiresAtMs, this.refreshToken, this.scope, this.idToken});

  factory OAuthTokens.fromResponse(Map<String, Object?> j, {String? previousRefreshToken, int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return OAuthTokens(
      accessToken: j['access_token'] as String? ?? '',
      refreshToken: j['refresh_token'] as String? ?? previousRefreshToken,
      expiresAtMs: now + ((j['expires_in'] as num?)?.toInt() ?? 3600) * 1000,
      scope: j['scope'] as String?,
      idToken: j['id_token'] as String?,
    );
  }

  factory OAuthTokens.fromJson(Map<String, Object?> j) => OAuthTokens(
        accessToken: j['access'] as String? ?? '',
        refreshToken: j['refresh'] as String?,
        expiresAtMs: (j['exp'] as num?)?.toInt() ?? 0,
        scope: j['scope'] as String?,
        idToken: j['id'] as String?,
      );

  final String accessToken;
  final String? refreshToken;
  final int expiresAtMs;
  final String? scope;
  final String? idToken;

  bool expiresWithin(Duration d, {int? nowMs}) => (nowMs ?? DateTime.now().millisecondsSinceEpoch) + d.inMilliseconds >= expiresAtMs;

  Map<String, Object?> toJson() => {'access': accessToken, 'refresh': refreshToken, 'exp': expiresAtMs, 'scope': scope, 'id': idToken};
}

/// PKCE verifier (RFC 7636): 64 chars of unreserved characters.
String pkceVerifier({Random? random}) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final r = random ?? Random.secure();
  return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
}

/// S256 challenge for a verifier.
String pkceChallenge(String verifier) => base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

/// Google OAuth for the Hub's web flow (SPEC §13.2).
class GoogleOAuth {
  GoogleOAuth(this.fetcher, {required this.clientId, required this.clientSecret});

  final Fetcher fetcher;
  final String clientId;
  final String clientSecret;
  static const provider = 'google-oauth';

  static const calendarScopes = [
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
    'https://www.googleapis.com/auth/calendar.events',
  ];
  static const photosPickerScope = 'https://www.googleapis.com/auth/photospicker.mediaitems.readonly';

  Uri authorizationUrl({required String redirectUri, required String state, required List<String> scopes, String? codeChallenge, String? loginHint}) =>
      Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes.join(' '),
        'access_type': 'offline',
        'prompt': 'consent',
        'include_granted_scopes': 'true',
        'state': state,
        'code_challenge': ?codeChallenge,
        if (codeChallenge != null) 'code_challenge_method': 'S256',
        'login_hint': ?loginHint,
      });

  Future<OAuthTokens> exchangeCode(String code, {required String redirectUri, String? codeVerifier}) async {
    final j = await fetcher.postJson(provider, Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'code': code,
      'client_id': clientId,
      'client_secret': clientSecret,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': ?codeVerifier,
    });
    return OAuthTokens.fromResponse(asObject(j, provider));
  }

  Future<OAuthTokens> refresh(String refreshToken) async {
    final j = await fetcher.postJson(provider, Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'refresh_token': refreshToken,
      'client_id': clientId,
      'client_secret': clientSecret,
      'grant_type': 'refresh_token',
    });
    return OAuthTokens.fromResponse(asObject(j, provider), previousRefreshToken: refreshToken);
  }

  Future<Map<String, Object?>> userInfo(String accessToken) async => asObject(
        await fetcher.getJson(provider, Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'), headers: {'Authorization': 'Bearer $accessToken'}),
        provider,
      );
}
