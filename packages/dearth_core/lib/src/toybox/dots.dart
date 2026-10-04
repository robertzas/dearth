import 'dart:math';

import 'package:meta/meta.dart';

import 'games.dart';

// Dot-to-Dot (SPEC FR-TOY-03, Appendix B: number order, numerals, alphabet
// order). She joins the dots in order, 1→5 up to 1→20, then A→M and A→Z,
// and the picture they make comes alive. The voice says each number or
// letter as it's joined, and which one to find after a wrong dot. The
// pictures and where their dots sit are drawn in the app.

/// A picture the dots make: [id] for the app's drawing, [phrase] for the
/// voice ("It's a star!"), [emoji] for the cheer.
@immutable
class DotPicture {
  const DotPicture(this.id, this.phrase, this.emoji);
  final String id;
  final String phrase;
  final String emoji;
}

const List<DotPicture> kDotPictures = [
  DotPicture('star', 'a star', '⭐'),
  DotPicture('heart', 'a heart', '❤️'),
  DotPicture('house', 'a house', '🏠'),
  DotPicture('fish', 'a fish', '🐟'),
  DotPicture('balloon', 'a balloon', '🎈'),
  DotPicture('apple', 'an apple', '🍎'),
  DotPicture('rocket', 'a rocket', '🚀'),
  DotPicture('whale', 'a whale', '🐳'),
  DotPicture('crown', 'a crown', '👑'),
  DotPicture('butterfly', 'a butterfly', '🦋'),
  DotPicture('cat', 'a cat', '🐱'),
  DotPicture('sun', 'the sun', '☀️'),
  DotPicture('umbrella', 'an umbrella', '☂️'),
  DotPicture('car', 'a car', '🚗'),
  DotPicture('icecream', 'an ice cream', '🍦'),
];

/// A level's dots, in order (Appendix B): 1→5, 1→10, 1→15, 1→20, then
/// A→M and A→Z.
List<String> dotLabels(int level) => switch (level) {
      <= 1 => _numbers(5),
      2 => _numbers(10),
      3 => _numbers(15),
      4 => _numbers(20),
      5 => _letters(13),
      _ => _letters(26),
    };

List<String> _numbers(int n) => [for (var i = 1; i <= n; i++) '$i'];
List<String> _letters(int n) => [for (var i = 0; i < n; i++) String.fromCharCode(0x41 + i)];

@immutable
class DotsRound {
  const DotsRound(this.picture, this.labels);
  final DotPicture picture;

  /// The dots, in the order she joins them.
  final List<String> labels;

  bool get letters => labels.first == 'A';
}

/// A round at [level]: a picture she hasn't made lately ([recent] ids).
DotsRound dotsRound(int level, Random rng, {Iterable<String> recent = const []}) {
  final fresh = [for (final p in kDotPictures) if (!recent.contains(p.id)) p];
  final pool = fresh.isEmpty ? kDotPictures : fresh;
  return DotsRound(pool[rng.nextInt(pool.length)], dotLabels(level));
}

/// A wrong dot is a slip. Long rounds forgive more: a win allows one slip
/// and one more per ten dots, "helped" about twice that, then a miss.
String dotsResult(int slips, int dots) {
  final spare = 1 + dots ~/ 10;
  if (slips <= spare) return GameResult.win;
  if (slips <= spare * 2 + 1) return GameResult.helped;
  return GameResult.miss;
}
