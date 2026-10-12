import 'dart:async';

import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// The HTTP layer every adapter shares (SPEC §13.1): what it retries, how
/// long it waits, and what it never repeats.
void main() {
  final waits = <Duration>[];
  Fetcher fetcher(Future<http.Response> Function(http.Request req) handler, {Duration timeout = const Duration(seconds: 20)}) {
    waits.clear();
    return Fetcher(client: MockClient(handler), timeout: timeout, sleep: (d) async => waits.add(d));
  }

  final url = Uri.parse('https://api.test/thing');

  test('a 5xx is retried twice with growing backoff, then reported', () async {
    var calls = 0;
    final f = fetcher((_) async {
      calls++;
      return http.Response('down', 502);
    });
    await expectLater(f.getJson('t', url), throwsA(isA<ProviderException>().having((e) => e.status, 'status', 502).having((e) => e.isRetryable, 'retryable', isTrue)));
    expect(calls, 3);
    expect(waits, hasLength(2));
    expect(waits[1], greaterThan(waits[0]));
  });

  test('a short Retry-After is honoured; a long one falls back to backoff', () async {
    var calls = 0;
    var f = fetcher((_) async => ++calls == 1 ? http.Response('', 429, headers: {'retry-after': '3'}) : http.Response('{"ok":true}', 200));
    expect(await f.getJson('t', url), {'ok': true});
    expect(waits, [const Duration(seconds: 3)]);

    calls = 0;
    f = fetcher((_) async => ++calls == 1 ? http.Response('', 429, headers: {'retry-after': '3600'}) : http.Response('{}', 200));
    await f.getJson('t', url);
    expect(waits.single, lessThan(const Duration(seconds: 30)), reason: 'an hour is not slept through');
  });

  test('4xx other than 429 are not retried, and are classified', () async {
    var calls = 0;
    final f = fetcher((_) async {
      calls++;
      return http.Response('nope', 404);
    });
    await expectLater(f.getJson('t', url), throwsA(isA<ProviderException>().having((e) => e.isNotFound, 'notFound', isTrue)));
    expect(calls, 1);
  });

  test('a timeout is retried, then reported as one', () async {
    var calls = 0;
    final f = fetcher((_) {
      calls++;
      return Completer<http.Response>().future; // never answers
    }, timeout: const Duration(milliseconds: 10));
    await expectLater(f.getJson('t', url), throwsA(isA<ProviderException>().having((e) => e.message, 'message', contains('Timed out'))));
    expect(calls, 3);
  });

  test('a POST that creates something is sent once, even when it fails', () async {
    var calls = 0;
    final f = fetcher((_) async {
      calls++;
      return http.Response('busy', 503);
    });
    await expectLater(f.postJson('t', url, body: <String, Object?>{'title': 'x'}, retry: false), throwsA(isA<ProviderException>()));
    expect(calls, 1, reason: 'Google may have applied it: no second copy');
    calls = 0;
    await expectLater(f.postJson('t', url, body: <String, Object?>{'q': 'x'}), throwsA(isA<ProviderException>()));
    expect(calls, 3, reason: 'idempotent posts still retry');
  });
}
