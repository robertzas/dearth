import 'dart:convert';
import 'dart:io';

import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A Fetcher whose network is a routing table: (method, url predicate) →
/// response. Unmatched requests fail loudly so tests never reach the
/// internet.
Fetcher fakeFetcher(Map<bool Function(http.Request), http.Response Function(http.Request)> routes, {List<http.Request>? log}) {
  final client = MockClient((req) async {
    log?.add(req);
    for (final e in routes.entries) {
      if (e.key(req)) return e.value(req);
    }
    return http.Response('no route for ${req.method} ${req.url}', 599);
  });
  return Fetcher(client: client, maxRetries: 1, sleep: (_) async {});
}

http.Response json(Object body, {int status = 200, Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

http.Response text(String body, {int status = 200}) => http.Response(body, status);

bool Function(http.Request) path(String p) => (r) => r.url.path == p;
bool Function(http.Request) pathEnds(String p) => (r) => r.url.path.endsWith(p);
