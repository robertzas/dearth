import 'dart:math';

import 'package:meta/meta.dart';

import 'expansion.dart';

// Big & Little Letters (SPEC FR-TOY-03, Appendix B: capitals and small
// letters). Capitals wait on cards; she brings each small letter to its
// capital and the voice names the pair ("Big C, little c."). The ladder
// starts with pairs that look alike, so the idea lands before the shapes
// get hard, then pairs that look different, then b, d, p and q, the
// mirror letters every early reader mixes up. Drawing lives in the app.

/// Small letters shaped like their capitals, only smaller.
const List<String> kLookAlikeLetters = ['c', 'k', 'o', 's', 'u', 'v', 'w', 'x', 'z'];

/// Small letters that don't look like their capitals.
const List<String> kDifferentLetters = ['a', 'e', 'f', 'g', 'h', 'i', 'j', 'l', 'm', 'n', 'r', 't', 'y'];

/// The mirror letters: one shape turned or flipped.
const List<String> kMirrorLetters = ['b', 'd', 'p', 'q'];

@immutable
class BigLittleRound {
  const BigLittleRound(this.letters, this.tray);

  /// The capitals' cards, left to right (as small letters).
  final List<String> letters;

  /// The small letters waiting below, in their own order.
  final List<String> tray;
}

/// A round at [level]: 3 look-alike pairs → 5 pairs that look different →
/// b, d, p and q. Never the same letters as [last], and no small letter
/// starts right under its own capital (that would match by position, not by
/// shape).
BigLittleRound bigLittleRound(int level, Random rng, {List<String> last = const []}) {
  final (pool, n) = switch (level) {
    <= 1 => (kLookAlikeLetters, 3),
    2 => (kDifferentLetters, 5),
    _ => (kMirrorLetters, 4),
  };
  List<String> pick() => ([...pool]..shuffle(rng)).take(n).toList();
  var letters = pick();
  // The mirror set is always the same four letters; a new order will do.
  for (var i = 0; i < 20 && _same(letters, last, ordered: pool.length == n); i++) {
    letters = pick();
  }
  bool underItsCapital(List<String> tray) => [for (var j = 0; j < n; j++) tray[j] == letters[j]].any((x) => x);
  var tray = [...letters]..shuffle(rng);
  for (var i = 0; i < 20 && underItsCapital(tray); i++) {
    tray.shuffle(rng);
  }
  // Shifted by one, every letter moves: a sure fallback.
  if (underItsCapital(tray)) tray = [...letters.skip(1), letters.first];
  return BigLittleRound(letters, tray);
}

bool _same(List<String> a, List<String> b, {required bool ordered}) {
  if (a.length != b.length) return false;
  if (ordered) return [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
  return a.toSet().containsAll(b);
}

/// As the other match-up games: three pairs want none wrong for a win (one
/// is "helped"); four or five pairs allow one.
String bigLittleResult(int slips, {required int pairs}) => expansionResult(slips, size: pairs);
