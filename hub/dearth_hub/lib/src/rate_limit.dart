import 'dart:io';

import 'package:shelf/shelf.dart';

/// Attempts per caller in a sliding window, for the unauthenticated edges
/// (pairing, the admin password). The 8-character pairing code and PBKDF2
/// make guessing slow already; this makes it hopeless, and keeps one caller
/// from filling the pairings table.
class RateLimiter {
  RateLimiter(this.max, this.window, {int Function()? now}) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int max;
  final Duration window;
  final int Function() _now;
  final Map<String, List<int>> _hits = {};

  List<int> _recent(String key) {
    final cutoff = _now() - window.inMilliseconds;
    final list = _hits[key];
    if (list == null) return const [];
    list.removeWhere((t) => t <= cutoff);
    if (list.isEmpty) _hits.remove(key);
    return list;
  }

  /// Whether [key] has used up its attempts. A null key (this machine) is
  /// never limited: local scripts and the Hub built into the app.
  bool blocked(String? key) => key != null && _recent(key).length >= max;

  void hit(String? key) {
    if (key == null) return;
    _recent(key);
    (_hits[key] ??= []).add(_now());
    // Forget idle callers so the map can't grow without end.
    if (_hits.length > 10000) _hits.removeWhere((k, _) => _recent(k).isEmpty);
  }
}

/// The caller's address, or null for loopback.
String? callerKey(Request r) {
  final info = r.context['shelf.io.connection_info'];
  if (info is! HttpConnectionInfo) return null;
  final a = info.remoteAddress;
  return a.isLoopback ? null : a.address;
}
