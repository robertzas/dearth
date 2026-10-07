import 'dart:math';

import 'package:meta/meta.dart';

import 'expansion.dart' show expansionResult;
import 'rounds.dart';
import 'tracing.dart' show nameGlyphs;

// Name Zoo (SPEC FR-TOY-03, Appendix B: reading first names). Animals
// queue at the zoo gate, and the one at the front needs its name card to
// go in. The voice spells a name, letter by letter, and she finds the card
// that says it: first her own name (the first word most children learn to
// read), then her family's and buddies' names, then a short name she
// builds from letter tiles. The names are the household's own, so the game
// can't say them (the clips are made offline); it spells them with the
// letter-name clips instead, which is the skill anyway. Drawing lives in
// the app.

enum ZooMode { own, family, build }

@immutable
class ZooRound {
  const ZooRound(this.mode, this.name, this.animal, {this.cards = const [], this.tiles = const []});
  final ZooMode mode;

  /// The name as the cards print it: a capital, then as written ("Ava").
  final String name;

  /// The animal at the gate.
  final String animal;

  /// The name cards to choose from (own and family), the answer among them.
  final List<String> cards;

  /// Build: the letters to pick from, the name's own and two more,
  /// shuffled.
  final List<String> tiles;

  List<String> get letters => name.split('');
}

/// Buddies' names: short, common, and easy to tell apart, to fill out a
/// small family's cards.
const List<String> kZooBuddies = [
  'Sam', 'Max', 'Leo', 'Zoe', 'Ben', 'Eva', 'Tom', 'Kim', 'Ivy', 'Jay', 'Mia', 'Noah', 'Lily', 'Finn', 'Ruby', 'Omar', 'Nia', 'Hugo', 'Rosa', 'Theo', //
];

/// The animals in the queue (Emoji 12 or older: the frame draws them).
const List<String> kZooAnimals = ['🦒', '🐘', '🦁', '🐧', '🐼', '🦓', '🐒', '🐢', '🦛', '🐨', '🦘', '🐻', '🦩', '🐯'];

/// [raw] as a name card prints it: its first word's letters, a capital
/// first, accents plain ("zoë" → "Zoe"); empty when it has none to show.
String zooName(String raw) {
  final first = raw.trim().split(RegExp(r'\s+')).first;
  final glyphs = nameGlyphs(first);
  return glyphs.length < 2 || glyphs.length > 8 ? '' : glyphs.join();
}

/// A round at [level] for a kid called [kid] with [family] (the household's
/// other names): her own name among three cards → a family or buddy name
/// among four → a name of up to five letters built from tiles. Never the
/// same name, or the same animal, twice running.
ZooRound zooRound(int level, Random rng, {required String kid, List<String> family = const [], ZooRound? last}) {
  final me = zooName(kid);
  final seen = <String>{if (me.isNotEmpty) me.toLowerCase()};
  final people = [
    for (final f in family.map(zooName))
      if (f.isNotEmpty && seen.add(f.toLowerCase())) f,
  ];
  final buddies = [for (final b in kZooBuddies) if (seen.add(b.toLowerCase())) b];
  final animal = _pick([for (final a in kZooAnimals) if (a != last?.animal) a], rng);
  final mode = switch (level) { <= 1 => me.isEmpty ? ZooMode.family : ZooMode.own, 2 => ZooMode.family, _ => ZooMode.build };
  switch (mode) {
    case ZooMode.own:
      // Her name stands out: the other cards start with other letters.
      final decoys = ([...people, ...buddies]..shuffle(rng)).where((n) => n[0] != me[0]).take(2);
      return ZooRound(mode, me, animal, cards: [me, ...decoys]..shuffle(rng));
    case ZooMode.family:
      final pool = people.isEmpty ? buddies : people;
      final name = _pick([for (final n in pool) if (n != last?.name) n], rng, fallback: pool.first);
      final others = [if (me.isNotEmpty) me, ...people, ...buddies].where((n) => n != name).toList()..shuffle(rng);
      // The family first among the other cards: those are the names she sees at home.
      others.sort((a, b) => (people.contains(b) ? 1 : 0).compareTo(people.contains(a) ? 1 : 0));
      return ZooRound(mode, name, animal, cards: [name, ...others.take(3)]..shuffle(rng));
    case ZooMode.build:
      final short = [if (me.isNotEmpty) me, ...people, ...buddies].where((n) => n.length <= 5 && n != last?.name).toList();
      // Her own and her family's names come up most.
      final close = short.where((n) => n == me || people.contains(n)).toList();
      final name = close.isNotEmpty && rng.nextDouble() < 0.6 ? _pick(close, rng) : _pick(short, rng);
      final used = name.toLowerCase().split('').toSet();
      final extra = ([for (final c in _extraLetters.split('')) if (!used.contains(c)) c]..shuffle(rng)).take(2);
      return ZooRound(mode, name, animal, tiles: [...name.split(''), ...extra]..shuffle(rng));
  }
}

/// Extra tiles: letters that don't look like each other's mirror images
/// (no b against d, p against q).
const String _extraLetters = 'aceghkmnorstuwz';

T _pick<T>(List<T> from, Random rng, {T? fallback}) => from.isEmpty ? fallback as T : from[rng.nextInt(from.length)];

/// Cards: one slip is fine among four, none among three (the host moves
/// the ladder). Building allows one slip over the whole name.
String zooResult(ZooRound r, int slips) => r.mode == ZooMode.build ? resultFor(slips, allowed: 1) : expansionResult(slips, size: r.cards.length);
