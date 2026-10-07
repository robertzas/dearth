import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's number and letter games (SPEC FR-TOY-03, Appendix B).
void main() {
  group('Dot-to-Dot', () {
    test('FR-TOY-03: 1→5, 1→10, 1→15, 1→20, then A→M and A→Z', () {
      expect(dotLabels(1), ['1', '2', '3', '4', '5']);
      expect(dotLabels(2), hasLength(10));
      expect(dotLabels(2).last, '10');
      expect(dotLabels(3).length, 15);
      expect(dotLabels(4).last, '20');
      expect(dotLabels(5), hasLength(13));
      expect(dotLabels(5).first, 'A');
      expect(dotLabels(5).last, 'M');
      expect(dotLabels(6), hasLength(26));
      expect(dotLabels(6).last, 'Z');
      for (final labels in [for (var l = 1; l <= 6; l++) dotLabels(l)]) {
        // In order and without repeats, so "number three" or "letter E" is
        // always findable.
        expect(labels.toSet().length, labels.length);
      }
    });

    test('a round never repeats a recent picture, and every picture has every level', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        var recent = <String>[];
        for (var level = 1; level <= 6; level++) {
          final r = dotsRound(level, rng, recent: recent);
          expect(r.labels, dotLabels(level));
          expect(r.picture.id, isNot(isIn(recent)), reason: 'seed $seed level $level must not reuse a recent picture');
          recent = [r.picture.id, ...recent].take(4).toList();
        }
      }
      // With everything recent it still deals a round.
      final r = dotsRound(1, Random(1), recent: [for (final p in kDotPictures) p.id]);
      expect(kDotPictures, contains(r.picture));
    });

    test('every picture says "It\'s a/an …!", with the right article', () {
      for (final p in kDotPictures) {
        expect(kVoiceLines[dotsDoneClip(p)], "It's ${p.phrase}!");
        final noun = p.phrase.replaceFirst(RegExp('^(an?|the) '), '');
        final article = RegExp('^[aeiou]').hasMatch(noun.toLowerCase()) ? 'an' : 'a';
        expect(p.phrase, anyOf(startsWith('$article '), startsWith('the ')), reason: '${p.id} wants "$article $noun"');
      }
      expect(kDotPictures.map((p) => p.id).toSet(), hasLength(kDotPictures.length), reason: 'no two pictures share an id');
    });

    test('slips: one spare slip and one more per ten dots, then helped, then a miss', () {
      expect(dotsResult(0, 5), GameResult.win);
      expect(dotsResult(1, 5), GameResult.win);
      expect(dotsResult(2, 5), GameResult.helped);
      expect(dotsResult(4, 5), GameResult.miss);
      expect(dotsResult(1, 10), GameResult.win);
      expect(dotsResult(2, 20), GameResult.win);
      expect(dotsResult(5, 20), GameResult.helped);
      expect(dotsResult(8, 26), GameResult.miss);
      expect(dotsResult(0, 26), GameResult.win);
    });
  });

  group('Big & Little Letters', () {
    test('FR-TOY-03: 3 look-alike pairs → 5 pairs that look different → b, d, p and q', () {
      expect({...kLookAlikeLetters, ...kDifferentLetters, ...kMirrorLetters}, hasLength(26), reason: 'every letter, once');
      for (final l in [...kLookAlikeLetters, ...kDifferentLetters, ...kMirrorLetters]) {
        expect(hasGlyph(l) && hasGlyph(l.toUpperCase()), isTrue, reason: l);
      }
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (final (level, pool, n) in [(1, kLookAlikeLetters, 3), (2, kDifferentLetters, 5), (3, kMirrorLetters, 4)]) {
          final r = bigLittleRound(level, rng);
          expect(r.letters, hasLength(n), reason: 'seed $seed, level $level');
          expect(r.letters.toSet(), hasLength(n), reason: 'no letter twice');
          expect(pool, containsAll(r.letters));
          expect(r.tray.toSet(), r.letters.toSet(), reason: 'a small letter for every capital');
          for (var i = 0; i < n; i++) {
            expect(r.tray[i], isNot(r.letters[i]), reason: 'seed $seed: ${r.tray[i]} starts under its own capital');
          }
        }
      }
    });

    test('a new round never deals the same letters again', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 3; level++) {
          final a = bigLittleRound(level, rng);
          final b = bigLittleRound(level, rng, last: a.letters);
          if (level < 3) {
            expect(b.letters.toSet().containsAll(a.letters), isFalse, reason: 'seed $seed, level $level');
          } else {
            expect(b.letters, isNot(a.letters), reason: 'the mirror four come in a new order');
          }
        }
      }
    });

    test('slips: three pairs want none for a win; four or five allow one', () {
      expect(bigLittleResult(0, pairs: 3), GameResult.win);
      expect(bigLittleResult(1, pairs: 3), GameResult.helped);
      expect(bigLittleResult(1, pairs: 5), GameResult.win);
      expect(bigLittleResult(1, pairs: 4), GameResult.win);
      expect(bigLittleResult(3, pairs: 4), GameResult.helped);
      expect(bigLittleResult(4, pairs: 5), GameResult.miss);
    });
  });

  group('Frog Hop', () {
    test('FR-TOY-03: pads 0–5 → 0–10 → one more or one less → adding 1–3 more', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          final r = hopRound(level, rng);
          final why = 'seed $seed, level $level';
          expect(r.pads, level == 1 ? 6 : 11, reason: why);
          expect(r.from, inInclusiveRange(0, r.pads - 1), reason: why);
          expect(r.target, inInclusiveRange(0, r.pads - 1), reason: why);
          expect(r.target, isNot(r.from), reason: 'the frog never starts on the answer ($why)');
          switch (level) {
            case 1 || 2:
              expect(r.mode, HopMode.find, reason: why);
            case 3:
              expect(r.mode, isIn([HopMode.oneMore, HopMode.oneLess]), reason: why);
              expect(r.target - r.from, r.mode == HopMode.oneMore ? 1 : -1, reason: why);
            default:
              expect(r.mode, HopMode.add, reason: why);
              expect(r.hops, inInclusiveRange(1, 3), reason: why);
              expect(r.from, greaterThan(0), reason: why);
              expect(r.target, lessThanOrEqualTo(10), reason: why);
          }
        }
      }
    });

    test('every pad, both neighbours and every sum come up; never the same target twice running', () {
      final seen = <String>{};
      for (var seed = 0; seed < 400; seed++) {
        final rng = Random(seed);
        int? last;
        for (var level = 1; level <= 4; level++) {
          for (var i = 0; i < 3; i++) {
            final r = hopRound(level, rng, last: last);
            if (i > 0) expect(r.target, isNot(last), reason: 'seed $seed, level $level');
            last = r.target;
            seen.add(hopAskClip(r));
          }
          last = null;
        }
      }
      expect(seen, hasLength(11 + 10 + 10 + kHopSums.length));
      expect(kHopSums, hasLength(9 + 8 + 7));
    });

    test('slips: right first time is a win, one slip is helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) hopResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
    });
  });

  group('Word Builder', () {
    test('FR-TOY-03: first letter missing → last → all three → four-letter words', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          final r = spellRound(level, rng);
          final why = 'seed $seed, level $level: ${r.letters} ${r.tiles}';
          expect(r.letters, hasLength(level >= 4 ? 4 : 3), reason: why);
          expect(r.missing, switch (level) { 1 => [0], 2 => [2], 3 => [0, 1, 2], _ => [0, 1, 2, 3] }, reason: why);
          expect(r.tiles, hasLength(r.missing.length + (r.missing.length == 1 ? 2 : 1)), reason: why);
          // Every missing letter has its tile (twice for "tent").
          final left = [...r.tiles];
          for (final i in r.missing) {
            expect(left.remove(r.letters[i]), isTrue, reason: why);
          }
          for (final extra in left) {
            expect(kSpellLetters, contains(extra), reason: why);
            expect(r.letters, isNot(contains(extra)), reason: why);
            if (r.missing.length == 1) expect('aeiou', isNot(contains(extra)), reason: 'a lone vowel would stand out ($why)');
          }
        }
      }
    });

    test('an extra letter never sounds like one in the word, nor spells another picture', () {
      const alike = ['bp', 'dt', 'cgk', 'fv', 'mn', 'sz'];
      for (var seed = 0; seed < 300; seed++) {
        for (var level = 1; level <= 4; level++) {
          final r = spellRound(level, Random(seed));
          final extras = [...r.tiles];
          for (final i in r.missing) {
            extras.remove(r.letters[i]);
          }
          for (final e in extras) {
            for (final l in r.letters.split('')) {
              expect(alike.any((g) => g.contains(e) && g.contains(l)), isFalse, reason: '$e against $l in ${r.letters}');
            }
            if (r.missing.length == 1) {
              final i = r.missing.single;
              final other = r.letters.replaceRange(i, i + 1, e);
              expect([...kSpellWords, ...kSpellLongWords], isNot(contains(other)), reason: '${r.letters}: $e would make $other');
            }
          }
        }
      }
    });

    test('every word comes up, never twice running, and is a picture with a clip', () {
      final seen = <String>{};
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          String? last;
          for (var i = 0; i < 4; i++) {
            final r = spellRound(level, rng, last: last);
            expect(r.letters, isNot(last));
            last = r.letters;
            seen.add(r.letters);
          }
        }
      }
      expect(seen, {...kSpellWords, ...kSpellLongWords});
      for (final w in [...kSpellWords, ...kSpellLongWords]) {
        expect(kWordsByName, contains(w));
        expect(kVoiceLines, contains(wordNamed(w).clip));
        // One letter per sound: every letter has a sound clip of its own.
        for (final l in w.split('')) {
          expect(kVoiceLines, contains(soundClip(l)), reason: '$w: $l');
        }
      }
      expect(kSpellWords.toSet(), hasLength(kSpellWords.length));
      expect(kSpellLongWords.toSet(), hasLength(kSpellLongWords.length));
    });

    test('slips: one letter is a pick-one round; a four-letter word allows one slip', () {
      expect([for (var s = 0; s <= 2; s++) spellResult(s, missing: 1)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect([for (var s = 0; s <= 2; s++) spellResult(s, missing: 3)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect([for (var s = 0; s <= 2; s++) spellResult(s, missing: 4)], [GameResult.win, GameResult.win, GameResult.helped]);
    });
  });

  group('Hear the Sound', () {
    test('FR-TOY-03: easy sounds → more sounds → a sound beside its look-alike → sh, ch and th', () {
      const pairs = [('b', 'p'), ('d', 't'), ('k', 'g'), ('f', 'v'), ('m', 'n')];
      bool paired(String a, String b) => pairs.any((p) => (p.$1 == a && p.$2 == b) || (p.$1 == b && p.$2 == a));
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          final r = hearRound(level, rng);
          final why = 'seed $seed, level $level: ${r.answer} ${r.choices}';
          expect(r.choices, contains(r.answer), reason: why);
          expect(r.choices.toSet(), hasLength(r.choices.length), reason: why);
          if (level < 4) expect(r.choices, everyElement(isNot(anyOf('c', 'q', 'x'))), reason: 'c says k, q and x need others ($why)');
          switch (level) {
            case 1:
              expect(r.choices, hasLength(2), reason: why);
              expect(kEasySounds, containsAll(r.choices), reason: why);
            case 2:
              expect(r.choices, hasLength(3), reason: why);
              expect(kMoreSounds, containsAll(r.choices), reason: why);
            case 3:
              expect(r.choices, hasLength(3), reason: why);
              expect(r.choices.where((c) => paired(c, r.answer)), hasLength(1), reason: 'its look-alike is there ($why)');
            default:
              expect(r.digraph, isTrue, reason: why);
              expect(r.choices, containsAll(['sh', 'ch', 'th']), reason: why);
              expect(r.choices, contains(r.answer[0]), reason: 'the near miss: its first letter alone ($why)');
          }
          if (level <= 2) {
            // Nothing alike to tell apart yet.
            for (final a in r.choices) {
              for (final b in r.choices) {
                expect(paired(a, b), isFalse, reason: why);
              }
            }
          }
        }
      }
    });

    test('every sound comes up, never twice running, and each has its lines', () {
      final seen = <String>{};
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          String? last;
          for (var i = 0; i < 3; i++) {
            final r = hearRound(level, rng, last: last);
            expect(r.answer, isNot(last));
            last = r.answer;
            seen.add(r.answer);
          }
        }
      }
      expect(seen, kHearAnswers.toSet());
      for (final a in kHearAnswers) {
        for (final clip in [hearAskClip(a), hearYesClip(a), soundClip(a)]) {
          expect(kVoiceLines, contains(clip));
        }
      }
      for (final d in kDigraphs) {
        expect(kWordsByName, contains(d.word));
      }
    });

    test('slips: right first time is a win, one slip is helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) hearResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
    });
  });

  group('Sight Words', () {
    test('FR-TOY-03: two letters → three → four → two-word labels, the decoys getting closer', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          final r = sightRound(level, rng);
          final why = 'seed $seed, level $level: ${r.word} ${r.signs}';
          expect(r.signs, contains(r.word), reason: why);
          expect(r.signs.toSet(), hasLength(r.signs.length), reason: why);
          expect(r.signs, hasLength(level == 1 ? 3 : 4), reason: why);
          final pool = switch (level) { 1 => kSightTwo, 2 => kSightThree, 3 => kSightFour, _ => kSightLabels };
          expect(pool, containsAll(r.signs), reason: why);
          if (level == 1) {
            expect({for (final w in r.signs) w[0].toLowerCase()}, hasLength(3), reason: 'the first letter tells them apart ($why)');
          }
          if (level == 3 && kSightFour.any((w) => w != r.word && w[0] == r.word[0])) {
            expect(r.signs.where((w) => w != r.word && w[0] == r.word[0]), isNotEmpty, reason: 'a look-alike start ($why)');
          }
          if (level == 4) {
            expect(r.signs.where((w) => w != r.word && w.split(' ').any(r.word.split(' ').contains)), isNotEmpty, reason: 'a label sharing a word ($why)');
          }
        }
      }
    });

    test('every word comes up, never twice running; every word has its lines and is drawable', () {
      final seen = <String>{};
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          String? last;
          for (var i = 0; i < 4; i++) {
            final r = sightRound(level, rng, last: last);
            expect(r.word, isNot(last));
            last = r.word;
            seen.add(r.word);
          }
        }
      }
      expect(seen, kSightWords.toSet());
      for (final w in kSightWords) {
        expect(kVoiceLines, contains(sightAskClip(w)));
        expect(kVoiceLines, contains(sightWordClip(w)));
        // Signs are written in the glyphs she traces.
        for (final c in w.replaceAll(' ', '').split('')) {
          expect(() => glyphFor(c), returnsNormally, reason: '$w: $c');
        }
      }
      expect(kSightWords.toSet(), hasLength(kSightWords.length));
    });

    test('slips: right first time is a win, one slip is helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) sightResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
    });
  });

  group('Banana Balance', () {
    test('FR-TOY-03: piles far apart → piles a banana apart → a pile against a numeral → two numerals', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          final r = balanceRound(level, rng);
          final why = 'seed $seed, level $level: ${r.left.count} ${r.right.count}';
          expect(r.left.count, isNot(r.right.count), reason: 'never a tie ($why)');
          expect(r.fewer, greaterThanOrEqualTo(1), reason: why);
          expect(r.more, lessThanOrEqualTo(level == 1 ? 5 : 10), reason: why);
          if (level == 1) expect(r.more - r.fewer, greaterThanOrEqualTo(2), reason: 'easy to see ($why)');
          final cards = [r.left.numeral, r.right.numeral].where((n) => n).length;
          expect(cards, switch (level) { 1 || 2 => 0, 3 => 1, _ => 2 }, reason: why);
        }
      }
    });

    test('the bigger side is left or right by chance; one-apart pairs come up; never the same pair twice running', () {
      var left = 0, oneApart = 0;
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        BalanceRound? last;
        for (var i = 0; i < 4; i++) {
          final r = balanceRound(2, rng, last: last);
          if (last != null) expect((r.more, r.fewer), isNot((last.more, last.fewer)));
          last = r;
          if (r.leftMore) left++;
          if (r.more - r.fewer == 1) oneApart++;
        }
      }
      expect(left, inInclusiveRange(480, 720), reason: 'about half of 1200');
      expect(oneApart, greaterThan(100));
      expect(kBalancePairs, hasLength(45));
      for (final (more, fewer) in kBalancePairs) {
        expect(kVoiceLines, contains(balanceMoreClip(more, fewer)));
      }
    });

    test('slips: right first time is a win, a slip is helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) balanceResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
    });
  });

  group('Who Has More?', () {
    test('FR-TOY-03: 0–9 → 0–20 with a teen → more or fewer, mixed → three buses to line up', () {
      final asks = <CompareAsk>{};
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('compare')!.levels; level++) {
          final r = compareRound(level, rng);
          final why = 'seed $seed, level $level: ${r.buses}';
          expect(r.buses, hasLength(level == 4 ? 3 : 2), reason: why);
          expect(r.buses.toSet(), hasLength(r.buses.length), reason: 'never two the same ($why)');
          expect(r.buses.every((n) => n >= 0 && n <= (level == 1 ? 9 : kCompareMax)), isTrue, reason: why);
          expect(r.lineUp, [...r.buses]..sort(), reason: why);
          if (level == 1) expect(r.lineUp.last - r.lineUp.first, greaterThanOrEqualTo(2), reason: 'neighbors are hard at 3½ ($why)');
          if (level >= 2) expect(r.lineUp.last, greaterThanOrEqualTo(10), reason: 'a teen on the bus ($why)');
          expect(r.ask, switch (level) { 1 || 2 => CompareAsk.more, 4 => CompareAsk.order, _ => isIn([CompareAsk.more, CompareAsk.fewer]) }, reason: why);
          if (level == 3) asks.add(r.ask);
          if (r.ask == CompareAsk.more) expect(r.buses[r.answer], r.lineUp.last, reason: why);
          if (r.ask == CompareAsk.fewer) expect(r.buses[r.answer], r.lineUp.first, reason: why);
        }
      }
      expect(asks, {CompareAsk.more, CompareAsk.fewer}, reason: 'level 3 mixes the two questions');
    });

    test('the answer stands left or right by chance; never the same buses twice running', () {
      var first = 0;
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        CompareRound? last;
        for (var i = 0; i < 4; i++) {
          final r = compareRound(2, rng, last: last);
          if (last != null) expect(r.lineUp, isNot(last.lineUp));
          last = r;
          if (r.answer == 0) first++;
        }
      }
      expect(first, inInclusiveRange(480, 720), reason: 'about half of 1200');
    });

    test('slips: two buses are counting rounds; lining up three allows one slip', () {
      const two = CompareRound(CompareAsk.more, [3, 7]), three = CompareRound(CompareAsk.order, [3, 7, 12]);
      expect([for (var s = 0; s <= 2; s++) compareResult(two, s)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect([for (var s = 0; s <= 4; s++) compareResult(three, s)], [GameResult.win, GameResult.win, GameResult.helped, GameResult.helped, GameResult.miss]);
    });
  });

  group('Name Zoo', () {
    const family = ['Mom', 'Dad', 'Biscuit'];

    test('names print as cards: the first word, a capital first, accents plain, two to eight letters', () {
      expect([for (final n in ['zoë', 'Mary Ann', 'Jo', 'A', 'Bartholomew', ' ava ', 'Ánh']) zooName(n)], ['Zoe', 'Mary', 'Jo', '', '', 'Ava', 'Anh']);
    });

    test('FR-TOY-03: her own name among three → a family name among four → a short name built from tiles', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        final own = zooRound(1, rng, kid: 'Ava', family: family);
        expect((own.mode, own.name, own.cards.length), (ZooMode.own, 'Ava', 3), reason: 'seed $seed');
        expect(own.cards, contains('Ava'));
        expect(own.cards.where((c) => c != 'Ava').every((c) => c[0] != 'A'), isTrue, reason: 'her name stands out: ${own.cards}');
        final fam = zooRound(2, rng, kid: 'Ava', family: family);
        expect(fam.mode, ZooMode.family);
        expect(family, contains(fam.name), reason: 'the family first');
        expect((fam.cards.length, fam.cards.toSet().length), (4, 4));
        expect(fam.cards, contains(fam.name));
        final build = zooRound(3, rng, kid: 'Ava', family: family);
        expect(build.mode, ZooMode.build);
        expect(build.name.length, inInclusiveRange(2, 5));
        expect(build.tiles.length, build.letters.length + 2);
        final left = [...build.tiles];
        for (final l in build.letters) {
          expect(left.remove(l), isTrue, reason: 'every letter has a tile: ${build.tiles} for ${build.name}');
        }
        expect(left.every((x) => !build.name.toLowerCase().contains(x)), isTrue, reason: 'extras are other letters');
        for (final r in [own, fam, build]) {
          expect(kZooAnimals, contains(r.animal));
        }
      }
    });

    test('a kid whose name won\'t print starts with family names; a small family borrows buddies; no repeats', () {
      expect(zooRound(1, Random(1), kid: 'X', family: family).mode, ZooMode.family);
      final alone = zooRound(2, Random(2), kid: 'Ava');
      expect(kZooBuddies, contains(alone.name));
      expect(alone.cards, hasLength(4));
      final big = ['Mom', 'Dad', 'Biscuit', 'Leo', 'Grandma'];
      for (var seed = 0; seed < 100; seed++) {
        final rng = Random(seed);
        ZooRound? last;
        for (var i = 0; i < 5; i++) {
          final r = zooRound(i.isEven ? 2 : 3, rng, kid: 'Ava', family: big, last: last);
          if (last != null) {
            expect(r.name, isNot(last.name));
            expect(r.animal, isNot(last.animal));
          }
          last = r;
        }
      }
    });

    test('slips: none among three cards, one among four, one over a built name', () {
      const three = ZooRound(ZooMode.own, 'Ava', '🦒', cards: ['Ava', 'Mom', 'Dad']);
      const four = ZooRound(ZooMode.family, 'Mom', '🦒', cards: ['Ava', 'Mom', 'Dad', 'Leo']);
      const build = ZooRound(ZooMode.build, 'Mom', '🦒', tiles: ['M', 'o', 'm', 'a', 't']);
      expect([for (var s = 0; s <= 2; s++) zooResult(three, s)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect([for (var s = 0; s <= 2; s++) zooResult(four, s)], [GameResult.win, GameResult.win, GameResult.helped]);
      expect([for (var s = 0; s <= 4; s++) zooResult(build, s)], [GameResult.win, GameResult.win, GameResult.helped, GameResult.helped, GameResult.miss]);
    });
  });
}
