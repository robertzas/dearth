import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Bus Stop (SPEC FR-TOY-03, Appendix B: first adding and taking away). Who
// Has More?'s double-decker pulls in with some kids in its windows, and the
// voice says how many. At the stop, kids get on (or off) one at a time
// while she watches; then "How many kids are on the bus now?" and three
// number cards. A story she sees is the first sum: three on the bus, two
// more get on. The decoy cards are the number it started with (the
// commonest slip: forgetting the change) and a neighbor. The ladder: get
// on, to five → get on, to ten → get off → some get off, then some get on.
// Drawing lives in the app.

enum BusStopMode { on, off, both }

@immutable
class BusStopRound {
  const BusStopRound(this.mode, {required this.start, this.on = 0, this.off = 0, required this.choices});
  final BusStopMode mode;

  /// Kids on the bus when it pulls in.
  final int start;

  /// Kids who get on, and who get off (off first).
  final int on, off;

  /// The number cards, the answer among them, never two the same.
  final List<int> choices;

  int get answer => start - off + on;
}

/// The bus's lower deck: ten windows.
const int kBusStopMax = 10;

/// A round at [level] (Appendix B ladder): 1–3 on the bus and 1–2 get on
/// (to five) → 2–6 and 1–4 get on (to ten) → 3–10 and 1–3 get off → 1–3
/// off, then 1–3 on. Never the same sum as [last].
BusStopRound busStopRound(int level, Random rng, {BusStopRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || (r.start, r.on, r.off) != (last.start, last.on, last.off) || i >= 20) return r;
  }
}

BusStopRound _round(int level, Random rng) {
  int between(int lo, int hi) => lo + rng.nextInt(hi - lo + 1);
  while (true) {
    final (mode, start, on, off) = switch (level) {
      <= 1 => (BusStopMode.on, between(1, 3), between(1, 2), 0),
      2 => (BusStopMode.on, between(2, 6), between(1, 4), 0),
      3 => (BusStopMode.off, between(3, kBusStopMax), 0, between(1, 3)),
      _ => (BusStopMode.both, between(3, 8), between(1, 3), between(1, 3)),
    };
    final answer = start - off + on;
    if (answer < 1 || answer > kBusStopMax || (level <= 1 && answer > 5)) continue;
    // The start (forgetting the change) and a neighbor of the answer.
    final cards = <int>{answer, start};
    final near = [answer - 1, answer + 1]..shuffle(rng);
    for (final n in [...near, answer + 2, answer - 2]) {
      if (cards.length >= 3) break;
      if (n >= 0 && n <= kBusStopMax) cards.add(n);
    }
    return BusStopRound(mode, start: start, on: on, off: off, choices: cards.toList()..shuffle(rng));
  }
}

/// Three cards: right first time is a win, one slip "helped", then a miss.
String busStopResult(int slips) => countingResult(slips);
