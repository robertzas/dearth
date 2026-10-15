import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Drum Count (SPEC FR-TOY-03, Appendix B: counting sounds and actions).
// Counting what she hears, not what she sees: a bear plays its big drum
// and she says how many beats. First the voice counts along; then she
// counts alone, watching; then she plays a number of beats herself; at the
// top the drummer hides behind a curtain and only her ears can count. No
// other game counts events in time, and toddlers count a drum gladly.

enum DrumMode {
  /// The bear drums, the voice counts along, she picks how many.
  countAlong,

  /// The bear drums in silence (but for the drum); she picks how many.
  watch,

  /// "Play four beats!": she drums, then stops; the bear listens.
  play,

  /// Behind a curtain: she hears the beats only.
  hidden,
}

@immutable
class DrumRound {
  const DrumRound(this.mode, this.beats, this.choices);
  final DrumMode mode;
  final int beats;

  /// Numbers to pick from (empty when she plays).
  final List<int> choices;
}

/// A round at [level]: 1–3 counted along → 1–5 watched → playing 1–5 →
/// 2–6 heard only. Never the same number twice in a row.
DrumRound drumRound(int level, Random rng, {DrumRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.beats != last.beats || i >= 20) return r;
  }
}

DrumRound _round(int level, Random rng) {
  final (mode, lo, hi, n) = switch (level) {
    <= 1 => (DrumMode.countAlong, 1, 3, 2),
    2 => (DrumMode.watch, 1, 5, 3),
    3 => (DrumMode.play, 1, 5, 0),
    _ => (DrumMode.hidden, 2, 6, 3),
  };
  final beats = lo + rng.nextInt(hi - lo + 1);
  if (n == 0) return DrumRound(mode, beats, const []);
  // Near misses: one more and one less before anything further.
  // Nearest first; which side comes first is a coin toss.
  final key = {for (var k = max(1, lo - 1); k <= hi + 1; k++) if (k != beats) k: (k - beats).abs() * 10 + rng.nextInt(10)};
  final others = key.keys.toList()..sort((a, b) => key[a]!.compareTo(key[b]!));
  final choices = [beats, ...others.take(n - 1)]..sort();
  return DrumRound(mode, beats, choices);
}

/// How long the bear waits after her last beat before it counts as done.
const Duration kDrumDoneAfter = Duration(milliseconds: 1600);

/// Picked or played right the first time is a win.
String drumResult(int slips) => countingResult(slips);
