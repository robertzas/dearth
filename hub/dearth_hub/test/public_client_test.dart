import 'dart:io';

import 'package:dearth_hub/src/public_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// URLs a device names reach only the public internet (SUGGESTIONS Hub §2).
void main() {
  test('private, loopback and link-local addresses are not public', () {
    for (final a in ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.1', '192.168.1.10', '169.254.169.254', '100.64.0.1', '0.0.0.0', '::1', '::', 'fe80::1', 'fd00::1', '::ffff:192.168.1.1']) {
      expect(isPrivateAddress(InternetAddress(a)), isTrue, reason: a);
    }
    for (final a in ['93.184.216.34', '172.32.0.1', '8.8.8.8', '2606:4700::1111']) {
      expect(isPrivateAddress(InternetAddress(a)), isFalse, reason: a);
    }
  });

  test('refuses a LAN address, even behind a public redirect', () async {
    final seen = <Uri>[];
    final client = PublicOnlyClient(
      inner: MockClient((req) async {
        seen.add(req.url);
        if (req.url.path == '/hop') return http.Response('', 302, headers: {'location': 'http://192.168.1.1/admin'});
        return http.Response('ok', 200);
      }),
      lookup: (host) async => host == 'router.lan' ? [InternetAddress('192.168.1.1')] : [InternetAddress('93.184.216.34')],
    );
    expect((await client.get(Uri.parse('http://example.test/page'))).body, 'ok');
    await expectLater(client.get(Uri.parse('http://127.0.0.1:8080/api/health')), throwsA(isA<http.ClientException>()));
    await expectLater(client.get(Uri.parse('http://router.lan/')), throwsA(isA<http.ClientException>()));
    await expectLater(client.get(Uri.parse('http://example.test/hop')), throwsA(isA<http.ClientException>()));
    expect(seen.map((u) => u.toString()), ['http://example.test/page', 'http://example.test/hop'], reason: 'the LAN hop is never requested');
  });

  test('a body past the cap stops', () async {
    final client = PublicOnlyClient(
      inner: MockClient((req) async => http.Response('x' * 2000, 200)),
      lookup: (_) async => [InternetAddress('93.184.216.34')],
      maxBytes: 1000,
    );
    await expectLater(client.get(Uri.parse('http://example.test/big')), throwsA(isA<http.ClientException>()));
  });
}
