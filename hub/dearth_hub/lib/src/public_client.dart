import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The HTTP client for URLs a device hands the Hub (the image proxy, recipe
/// import). Any paired device can name one, kid-room displays included, so
/// it only reaches the public internet: an address on the Hub's own network
/// (the router's admin page, Home Assistant, the Hub itself) is refused,
/// redirects are followed here and checked hop by hop, and a body stops at
/// [maxBytes] instead of filling memory. Integrations the family configured
/// (Immich on the LAN, Home Assistant) keep the ordinary client.
class PublicOnlyClient extends http.BaseClient {
  PublicOnlyClient({http.Client? inner, this.maxBytes = 16 << 20, this.maxRedirects = 5, Future<List<InternetAddress>> Function(String host)? lookup})
      : _inner = inner ?? http.Client(),
        _lookup = lookup ?? InternetAddress.lookup;

  final http.Client _inner;
  final int maxBytes;
  final int maxRedirects;
  final Future<List<InternetAddress>> Function(String host) _lookup;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var url = request.url;
    for (var hop = 0;; hop++) {
      await _checkPublic(url);
      final req = http.Request(request.method, url)
        ..headers.addAll(request.headers)
        ..followRedirects = false;
      if (hop == 0 && request is http.Request && request.bodyBytes.isNotEmpty) req.bodyBytes = request.bodyBytes;
      final res = await _inner.send(req);
      final location = res.headers['location'];
      if (res.statusCode >= 300 && res.statusCode < 400 && location != null) {
        await res.stream.drain<void>();
        if (hop >= maxRedirects) throw http.ClientException('Too many redirects', url);
        url = url.resolve(location);
        continue;
      }
      final declared = res.contentLength;
      if (declared != null && declared > maxBytes) {
        unawaited(res.stream.drain<void>().catchError((Object _) {}));
        throw http.ClientException('Response too large', url);
      }
      return http.StreamedResponse(
        _capped(res.stream, url),
        res.statusCode,
        contentLength: declared,
        request: res.request,
        headers: res.headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
    }
  }

  Stream<List<int>> _capped(Stream<List<int>> body, Uri url) async* {
    var total = 0;
    await for (final chunk in body) {
      total += chunk.length;
      if (total > maxBytes) throw http.ClientException('Response too large', url);
      yield chunk;
    }
  }

  Future<void> _checkPublic(Uri url) async {
    if (!url.isScheme('https') && !url.isScheme('http')) throw http.ClientException('Only http(s) URLs', url);
    final literal = InternetAddress.tryParse(url.host);
    final addresses = literal != null ? [literal] : await _lookup(url.host);
    if (addresses.isEmpty || addresses.any(isPrivateAddress)) throw http.ClientException('Not a public address', url);
  }

  @override
  void close() => _inner.close();
}

/// Loopback, private (RFC 1918, unique-local), link-local, carrier-grade
/// NAT and unspecified addresses: everything that isn't the public internet.
bool isPrivateAddress(InternetAddress a) {
  var bytes = a.rawAddress;
  // IPv4-mapped IPv6 (::ffff:10.0.0.1) is checked as the IPv4 it carries.
  if (bytes.length == 16 && bytes.sublist(0, 10).every((b) => b == 0) && bytes[10] == 0xff && bytes[11] == 0xff) bytes = bytes.sublist(12);
  if (bytes.length == 4) {
    final (b0, b1) = (bytes[0], bytes[1]);
    return b0 == 0 ||
        b0 == 10 ||
        b0 == 127 ||
        (b0 == 100 && b1 >= 64 && b1 < 128) ||
        (b0 == 169 && b1 == 254) ||
        (b0 == 172 && b1 >= 16 && b1 < 32) ||
        (b0 == 192 && b1 == 168) ||
        b0 >= 224;
  }
  if (bytes.every((b) => b == 0)) return true; // ::
  if (bytes.sublist(0, 15).every((b) => b == 0) && bytes[15] == 1) return true; // ::1
  return (bytes[0] & 0xfe) == 0xfc || (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) || bytes[0] == 0xff;
}
