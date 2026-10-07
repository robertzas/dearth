import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Who Has More? (SPEC FR-TOY-03, Appendix B: comparing numerals). Buses
// pull in to the stop, each with its route number on the roof: the number
// of kids riding it. The voice names each number as its bus arrives, then
// asks which bus has more kids (later fewer). The windows stay empty until
// she answers or slips; then the kids show, ten to a deck, so the numeral
// she compared becomes a quantity she can see. Banana Balance starts from
// piles; this game starts from the numerals and goes past ten. The top
// level lines three buses up, fewest first. Drawing lives in the app.

enum CompareAsk { more, fewer, order }

@immutable
class CompareRound {
  const CompareRound(this.ask, this.buses);
  final CompareAsk ask;

  /// The numbers on the buses, in the order they stand; never two the same.
  final List<int> buses;

  /// The bus to tap (more and fewer): its index in [buses].
  int get answer {
    final pick = ask == CompareAsk.fewer ? buses.reduce(min) : buses.reduce(max);
    return buses.indexOf(pick);
  }

  /// The buses fewest first: the order she lines them up in.
  List<int> get lineUp => [...buses]..sort();
}

/// The highest number on a bus: two decks of ten windows.
const int kCompareMax = 20;

/// A round at [level] (Appendix B ladder): two buses of 0–9 at least two
/// apart, "which has more?" → 0–20 with one in the teens → more or fewer,
/// mixed → three buses to line up. Not the same numbers as [last].
CompareRound compareRound(int level, Random rng, {CompareRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    final same = last != null && _key(r) == _key(last);
    if (!same || i >= 20) return r;
  }
}

String _key(CompareRound r) => r.lineUp.join(',');

CompareRound _round(int level, Random rng) {
  final ask = switch (level) { <= 2 => CompareAsk.more, 3 => rng.nextBool() ? CompareAsk.more : CompareAsk.fewer, _ => CompareAsk.order };
  final count = ask == CompareAsk.order ? 3 : 2;
  while (true) {
    final buses = [for (var i = 0; i < count; i++) rng.nextInt(level <= 1 ? 10 : kCompareMax + 1)];
    final sorted = [...buses]..sort();
    var gap = kCompareMax;
    for (var i = 1; i < sorted.length; i++) {
      gap = min(gap, sorted[i] - sorted[i - 1]);
    }
    // Level 1 keeps neighbors apart (3 against 4 is hard at three and a
    // half); after that a teen is always on the bus, or the new level
    // would often look like the old one.
    if (gap < (level <= 1 ? 2 : 1)) continue;
    if (level >= 2 && sorted.last < 10) continue;
    return CompareRound(ask, buses);
  }
}

/// Two buses: right first time is a win, a slip is "helped". Lining up
/// three takes three picks, so one slip is still a win.
String compareResult(CompareRound r, int slips) => r.ask == CompareAsk.order ? resultFor(slips, allowed: 1) : countingResult(slips);
