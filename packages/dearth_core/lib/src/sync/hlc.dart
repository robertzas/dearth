import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Hybrid Logical Clock timestamp (SPEC §8.4.1).
///
/// Encoded as a fixed-width, lexically sortable string:
/// `"{millis:012x}{counter:04x}-{node}"`. Comparing two encoded strings gives
/// the same order as comparing the timestamps, with the node id breaking ties.
@immutable
class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.node);

  factory Hlc.zero(String node) => Hlc(0, 0, node);

  static Hlc parse(String packed) {
    if (packed.length < 18 || packed[16] != '-') {
      throw FormatException('Invalid HLC', packed);
    }
    return Hlc(
      int.parse(packed.substring(0, 12), radix: 16),
      int.parse(packed.substring(12, 16), radix: 16),
      packed.substring(17),
    );
  }

  static Hlc? tryParse(String? packed) {
    if (packed == null) return null;
    try {
      return parse(packed);
    } on FormatException {
      return null;
    }
  }

  static const int maxCounter = 0xFFFF;

  final int millis;
  final int counter;
  final String node;

  String pack() =>
      '${millis.toRadixString(16).padLeft(12, '0')}${counter.toRadixString(16).padLeft(4, '0')}-$node';

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return node.compareTo(other.node);
  }

  @override
  bool operator ==(Object other) =>
      other is Hlc && other.millis == millis && other.counter == counter && other.node == node;

  @override
  int get hashCode => Object.hash(millis, counter, node);

  @override
  String toString() => pack();
}

/// Thrown when a remote timestamp is implausibly far in the future.
class ClockDriftException implements Exception {
  ClockDriftException(this.remote, this.driftMs);
  final Hlc remote;
  final int driftMs;
  @override
  String toString() => 'ClockDriftException: ${remote.pack()} is ${driftMs}ms ahead';
}

/// A node's clock. [tick] stamps local events; [observe] merges remote stamps.
class HlcClock {
  HlcClock(this.node, {int Function()? wallClock, this.maxDriftMs = 10 * 60 * 1000})
      : _wall = wallClock ?? _systemMs,
        _last = Hlc.zero(node) {
    if (node.isEmpty) throw ArgumentError.value(node, 'node', 'must be non-empty');
  }

  static int _systemMs() => DateTime.now().millisecondsSinceEpoch;

  final String node;
  final int maxDriftMs;
  final int Function() _wall;
  Hlc _last;

  Hlc get last => _last;

  /// Timestamp for a new local event (strictly greater than anything seen).
  Hlc tick() {
    final wall = _wall();
    if (wall > _last.millis) {
      _last = Hlc(wall, 0, node);
    } else {
      _last = _bump(_last.millis, _last.counter);
    }
    return _last;
  }

  /// Advances the clock past a remote timestamp. Throws [ClockDriftException]
  /// if [remote] is more than [maxDriftMs] ahead of the wall clock.
  void observe(Hlc remote) {
    final wall = _wall();
    if (remote.millis - wall > maxDriftMs) {
      throw ClockDriftException(remote, remote.millis - wall);
    }
    final ms = math.max(wall, math.max(_last.millis, remote.millis));
    if (ms == _last.millis && ms == remote.millis) {
      _last = _bump(ms, math.max(_last.counter, remote.counter));
    } else if (ms == _last.millis) {
      _last = _bump(ms, _last.counter);
    } else if (ms == remote.millis) {
      _last = _bump(ms, remote.counter);
    } else {
      _last = Hlc(ms, 0, node);
    }
  }

  Hlc _bump(int millis, int counter) =>
      counter >= Hlc.maxCounter ? Hlc(millis + 1, 0, node) : Hlc(millis, counter + 1, node);
}
