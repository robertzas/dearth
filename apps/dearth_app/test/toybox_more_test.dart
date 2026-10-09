import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/busstop.dart';
import 'package:dearth_app/features/toybox/games/cookies.dart';
import 'package:dearth_app/features/toybox/games/lettermonster.dart';
import 'package:dearth_app/features/toybox/games/rocket.dart';
import 'package:dearth_app/features/toybox/games/train.dart';
import 'package:dearth_app/features/toybox/games/wordpop.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's second set of number and letter games (SPEC FR-TOY-03,
/// Appendix B), built on the games played most, played through the Toybox
/// on the demo household. What they say is checked by clip id.
void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
    testWidgets('every game of the second set lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
      await expectGamesLayOut(tester, const [('cookies', 1), ('cookies', 3), ('cookies', 4), ('lettermonster', 1), ('lettermonster', 2), ('lettermonster', 4), ('busstop', 1), ('busstop', 4), ('wordpop', 1), ('wordpop', 4), ('rocket', 1), ('rocket', 4), ('train', 1), ('train', 4)], size: size);
    });
  }

  group('Cookie Count', () {
    CookieGameState game(WidgetTester tester) => tester.state<CookieGameState>(find.byType(CookieGame));

    /// Taps the jar [n] times, a beat apart, as she would.
    Future<void> fill(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.tap(byId('cookies.jar'));
        await tester.pump(const Duration(milliseconds: 400));
      }
      // Let the last one land: cookies in flight ignore taps.
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('FR-TOY-03: the monster asks for a number; each cookie from the jar says the count; the bell serves the plate and it eats them', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'cookies', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      expect(game(tester).debugSpots, isTrue, reason: 'level 1 shows a spot for each cookie');
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [cookieAskClip(r.want)]);
      expect(labelOf(tester, 'cookies.ask'), 'I want ${r.want} cookie${r.want == 1 ? '' : 's'}');
      await tester.pump(afterVoice(cookieAskClip(r.want)));
      expect(sound.said.last, VoiceLine.cookiesBell, reason: 'the bell is explained once');
      await fill(tester, r.want);
      expect(game(tester).debugPlate, r.want);
      expect(sound.said.sublist(sound.said.length - r.want), [for (var n = 1; n <= r.want; n++) numberClip(n)]);
      expect(labelOf(tester, 'cookies.plate'), 'Plate: ${r.want} cookie${r.want == 1 ? '' : 's'}');
      await tester.tap(byId('cookies.bell'));
      await tester.pump();
      expect(sound.played.any((p) => p.$1 == Sfx.ding), isTrue);
      expect(sound.said.last, cookieYumClip(r.want));
      expect(labelOf(tester, 'cookies.ask'), 'Yum! ${r.want} cookie${r.want == 1 ? '' : 's'}');
      await tester.pump(const Duration(seconds: 3));
      expect(sound.played.where((p) => p.$1 == Sfx.munch), hasLength(r.want), reason: 'one munch a cookie');
      await h.settle();
      expect(await toyboxRounds(h), [('cookies', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      expect(game(tester).debugSolved, isFalse, reason: 'a new order comes');
      expect(sound.said.where((c) => c == VoiceLine.cookiesBell), hasLength(1), reason: 'only once a session');
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a short plate asks for more and keeps the cookies; a cookie tapped goes back; two wrong rings show the spots; the round is a miss', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'cookies', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(game(tester).debugSpots, isFalse);
      await tester.pump(const Duration(seconds: 4));
      await fill(tester, r.want - 1);
      await tester.tap(byId('cookies.bell'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, cookieMoreClip(r.want));
      expect(sound.played.where((p) => p.$1 == Sfx.nope), hasLength(1));
      expect(game(tester).debugPlate, r.want - 1, reason: 'she fixes the plate, it isn\'t emptied');
      expect(game(tester).debugSpots, isFalse);
      // Take one back off the plate (it says the new count) and ring again.
      await tester.tap(byId('cookies.cookie.${r.want - 2}'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(sound.said.last, numberClip(r.want - 2));
      expect(game(tester).debugPlate, r.want - 2);
      await tester.tap(byId('cookies.bell'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, cookieMoreClip(r.want));
      expect(game(tester).debugSpots, isTrue, reason: 'after two slips the plate shows where they go');
      await fill(tester, 2);
      expect(game(tester).debugPlate, r.want);
      await tester.tap(byId('cookies.bell'));
      await tester.pump(const Duration(seconds: 4));
      await h.settle();
      expect(await toyboxRounds(h), [('cookies', 3, 'miss')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the top level starts with cookies on the plate; an empty ring only asks again; a long pause asks again', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'cookies', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.start, isNot(r.want));
      expect(game(tester).debugPlate, r.start);
      expect(labelOf(tester, 'cookies.plate'), 'Plate: ${r.start} cookie${r.start == 1 ? '' : 's'}');
      await tester.pump(const Duration(seconds: 4));
      final asked = sound.said.where((c) => c == cookieAskClip(r.want)).length;
      await tester.pump(const Duration(seconds: 12));
      expect(sound.said.where((c) => c == cookieAskClip(r.want)).length, asked + 1, reason: 'asked again after a pause');
      if (r.start > r.want) {
        for (var i = r.start - 1; i >= r.want; i--) {
          await tester.tap(byId('cookies.cookie.$i'));
          await tester.pump(const Duration(milliseconds: 500));
        }
      } else {
        await fill(tester, r.want - r.start);
      }
      expect(game(tester).debugPlate, r.want);
      await tester.tap(byId('cookies.bell'));
      await tester.pump(const Duration(seconds: 4));
      await h.settle();
      expect(await toyboxRounds(h), [('cookies', 4, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('ringing an empty plate asks again and counts for nothing; a full plate shakes the jar and is too many', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'cookies', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(byId('cookies.bell'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, cookieAskClip(r.want));
      expect(sound.played.where((p) => p.$1 == Sfx.nope), isEmpty, reason: 'not a slip');
      await fill(tester, kCookiePlate + 1);
      expect(game(tester).debugPlate, kCookiePlate);
      expect(sound.played.where((p) => p.$1 == Sfx.boing), hasLength(1));
      // Level 2 wants two to five: a full plate is too many.
      await tester.tap(byId('cookies.bell'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, cookieFewerClip(r.want));
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
    });
  });

  group('Letter Monster', () {
    LetterMonsterGameState game(WidgetTester tester) => tester.state<LetterMonsterGameState>(find.byType(LetterMonsterGame));

    testWidgets('FR-TOY-03: the monster asks for a letter by name; the right biscuit is munched and the voice says its sound', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'lettermonster', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [letterMonsterAskClip(r)]);
      expect(labelOf(tester, 'lettermonster.ask'), 'I want the letter ${r.letter}');
      expect(labelOf(tester, 'lettermonster.food.${r.choices.indexOf(r.letter)}'), 'Letter ${r.letter}', reason: 'capitals at level 1');
      await tester.tap(byId('lettermonster.food.${r.choices.indexOf(r.letter)}'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(sound.played.where((p) => p.$1 == Sfx.munch), hasLength(1));
      expect(labelOf(tester, 'lettermonster.ask'), 'Yum! ${r.letter}');
      await tester.pump(const Duration(milliseconds: 600));
      expect(sound.said.last, letterClip(r.letter));
      await h.settle();
      expect(await toyboxRounds(h), [('lettermonster', 1, 'win')]);
      await tester.pump(const Duration(seconds: 5));
      expect(game(tester).debugEaten, isFalse, reason: 'a new tray comes');
      await tester.pump(const Duration(seconds: 13));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a wrong biscuit is refused and says its name; two slips light the answer; the round is a miss', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'lettermonster', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.ask, LetterMonsterAsk.sound);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.last, letterMonsterAskClip(r));
      expect(labelOf(tester, 'lettermonster.food.0'), 'Letter ${r.choices[0].toLowerCase()}', reason: 'small letters from level 2');
      final wrong = [for (var i = 0; i < r.choices.length; i++) if (r.choices[i] != r.letter) i];
      for (final (k, i) in wrong.take(2).indexed) {
        await tester.tap(byId('lettermonster.food.$i'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(sound.said.last, letterNameClip(r.choices[i]));
        expect(sound.played.where((p) => p.$1 == Sfx.nope), hasLength(k + 1));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(game(tester).debugHint, isTrue);
      await tester.tap(byId('lettermonster.food.${r.choices.indexOf(r.letter)}'));
      await tester.pump(const Duration(seconds: 1));
      await h.settle();
      expect(await toyboxRounds(h), [('lettermonster', 3, 'miss')]);
      await tester.pump(const Duration(seconds: 18));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the top level shows a picture and asks for its first sound; dragging the biscuit to the mouth feeds it', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'lettermonster', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.ask, LetterMonsterAsk.picture);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.last, firstSoundClip(r.word!));
      final from = tester.getCenter(byId('lettermonster.food.${r.choices.indexOf(r.letter)}'));
      final to = tester.getCenter(byId('lettermonster.mouth'));
      final gesture = await tester.startGesture(from);
      for (var k = 1; k <= 10; k++) {
        await gesture.moveTo(Offset.lerp(from, to, k / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(game(tester).debugEaten, isTrue);
      await h.settle();
      expect(await toyboxRounds(h), [('lettermonster', 4, 'win')]);
      await tester.pump(const Duration(seconds: 18));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a long pause asks again and lights the answer, without a slip', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'lettermonster', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(seconds: 13));
      expect(game(tester).debugHint, isTrue);
      expect(sound.said.where((c) => c == letterMonsterAskClip(r)), hasLength(2));
      await tester.tap(byId('lettermonster.food.${r.choices.indexOf(r.letter)}'));
      await tester.pump(const Duration(seconds: 1));
      await h.settle();
      expect(await toyboxRounds(h), [('lettermonster', 2, 'win')]);
      await tester.pump(const Duration(seconds: 18));
      await h.shutdown();
    });
  });

  group('Bus Stop', () {
    BusStopGameState game(WidgetTester tester) => tester.state<BusStopGameState>(find.byType(BusStopGame));

    /// Lets the bus pull in and the kids get on and off until the question.
    Future<void> untilAsked(WidgetTester tester) async {
      for (var i = 0; i < 200 && !game(tester).debugAsked; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game(tester).debugAsked, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
    }

    int index(BusStopRound r, int n) => r.choices.indexOf(n);

    testWidgets('FR-TOY-03: the bus says how many are on board, kids climb on one by one, and the right card answers how many now', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'busstop', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      expect(labelOf(tester, 'busstop.ask'), 'Here comes the bus');
      expect(game(tester).debugOnBus, r.start);
      await untilAsked(tester);
      expect(sound.said, [busStartClip(r.start), busOnClip(r.on), VoiceLine.busStopAsk]);
      expect(sound.played.where((p) => p.$1 == Sfx.pop), hasLength(r.on), reason: 'a pop as each kid climbs on');
      expect(game(tester).debugOnBus, r.answer);
      expect(labelOf(tester, 'busstop.bus'), 'Bus: ${r.answer} kid${r.answer == 1 ? '' : 's'}');
      expect(labelOf(tester, 'busstop.ask'), 'How many kids are on the bus now?');
      await tester.tap(byId('busstop.card.${index(r, r.answer)}'));
      await tester.pump();
      expect(sound.said.last, busNowClip(r.answer));
      expect(labelOf(tester, 'busstop.ask'), '${r.answer} kid${r.answer == 1 ? '' : 's'} on the bus');
      await h.settle();
      expect(await toyboxRounds(h), [('busstop', 1, 'win')]);
      await tester.pump(const Duration(seconds: 5));
      expect(game(tester).debugAsked, isFalse, reason: 'the bus drives off and the next one comes');
      await tester.pump(const Duration(seconds: 20));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('kids get off; a wrong card says its number, the windows light as the voice counts, the right card glows; helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'busstop', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.mode, BusStopMode.off);
      await untilAsked(tester);
      expect(sound.said, [busStartClip(r.start), busOffClip(r.off), VoiceLine.busStopAsk]);
      expect(game(tester).debugOnBus, r.answer);
      final wrong = r.choices.firstWhere((c) => c != r.answer);
      await tester.tap(byId('busstop.card.${index(r, wrong)}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, numberClip(wrong));
      expect(sound.played.where((p) => p.$1 == Sfx.nope), hasLength(1));
      for (var i = 0; i < 120 && !game(tester).debugHint; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game(tester).debugHint, isTrue);
      final counted = sound.said.skipWhile((c) => c != numberClip(wrong)).skip(1).toList();
      expect(counted, [for (var k = 1; k <= r.answer; k++) numberClip(k)], reason: 'one number a window');
      await tester.tap(byId('busstop.card.${index(r, r.answer)}'));
      await tester.pump(const Duration(seconds: 1));
      await h.settle();
      expect(await toyboxRounds(h), [('busstop', 3, 'helped')]);
      await tester.pump(const Duration(seconds: 25));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the top level: some get off, then some get on; a long pause asks again', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'busstop', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.mode, BusStopMode.both);
      await untilAsked(tester);
      expect(sound.said, [busStartClip(r.start), busOffClip(r.off), busOnClip(r.on), VoiceLine.busStopAsk]);
      expect(game(tester).debugOnBus, r.answer);
      await tester.pump(const Duration(seconds: 12));
      expect(sound.said.where((c) => c == VoiceLine.busStopAsk), hasLength(2));
      await tester.tap(byId('busstop.bus'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.honk);
      await tester.tap(byId('busstop.card.${index(r, r.answer)}'));
      await tester.pump(const Duration(seconds: 1));
      await h.settle();
      expect(await toyboxRounds(h), [('busstop', 4, 'win')]);
      await tester.pump(const Duration(seconds: 25));
      await h.shutdown();
    });
  });

  group('Word Pop', () {
    WordPopGameState game(WidgetTester tester) => tester.state<WordPopGameState>(find.byType(WordPopGame));

    /// Taps a bubble that says [word] (or, with [not], one that doesn't),
    /// waiting for one to be well up on the screen.
    Future<void> popOne(WidgetTester tester, String word, {bool not = false}) async {
      for (var i = 0; i < 80; i++) {
        final up = game(tester).debugBubbles.where((b) => (b.$2 == word) != not && b.$3.dy > 200 && b.$3.dy < 700).toList();
        if (up.isNotEmpty) {
          await tester.tap(byId('wordpop.bubble.${up.first.$1}'));
          await tester.pump(const Duration(milliseconds: 50));
          return;
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
      fail('no bubble ${not ? 'without' : 'with'} "$word" came up');
    }

    testWidgets('FR-TOY-03: the voice asks for a word; each bubble that says it pops and reads it; three finish the round', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'wordpop', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [sightAskClip(r.word)]);
      expect(labelOf(tester, 'wordpop.ask'), 'Pop the word ${r.word}: 0 of $kWordPops');
      expect(game(tester).debugBubbles.where((b) => b.$2 == r.word).length, greaterThanOrEqualTo(2), reason: 'always two to find');
      for (var k = 1; k <= kWordPops; k++) {
        await popOne(tester, r.word);
        expect(game(tester).debugPopped, k);
        expect(sound.said.last, sightWordClip(r.word));
      }
      expect(sound.played.where((p) => p.$1 == Sfx.pop), hasLength(kWordPops));
      expect(labelOf(tester, 'wordpop.ask'), 'Popped ${r.word}: $kWordPops of $kWordPops');
      await h.settle();
      expect(await toyboxRounds(h), [('wordpop', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      expect(game(tester).debugPopped, 0, reason: 'a new word');
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('another word bounces and reads itself; two slips ring the right bubbles; the round is helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'wordpop', sound: sound, level: 3);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      for (var k = 1; k <= 2; k++) {
        await popOne(tester, r.word, not: true);
        expect(sound.said.last, isNot(sightWordClip(r.word)));
        expect(r.words.map(sightWordClip), contains(sound.said.last), reason: 'it reads its own word');
        expect(sound.played.where((p) => p.$1 == Sfx.nope), hasLength(k));
        expect(game(tester).debugPopped, 0);
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(game(tester).debugHint, isTrue);
      for (var k = 0; k < kWordPops; k++) {
        await popOne(tester, r.word);
      }
      await h.settle();
      expect(await toyboxRounds(h), [('wordpop', 3, 'helped')]);
      await tester.pump(const Duration(seconds: 16));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a long pause asks again and rings the bubbles, without a slip', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'wordpop', sound: sound, level: 2);
      final r = game(tester).debugRound;
      for (var i = 0; i < 110; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game(tester).debugHint, isTrue);
      expect(sound.said.where((c) => c == sightAskClip(r.word)), hasLength(2));
      expect(sound.played.where((p) => p.$1 == Sfx.nope), isEmpty);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
    });
  });

  group('Rocket Countdown', () {
    RocketGameState game(WidgetTester tester) => tester.state<RocketGameState>(find.byType(RocketGame));

    testWidgets('FR-TOY-03: "Count down from five!"; each star in order says its number and plays a higher note; at one, blast off', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'rocket', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expect(r.start, 5);
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [rocketStartClip(5)]);
      expect(labelOf(tester, 'rocket.ask'), 'Count down from 5: next 5');
      for (final n in r.countdown) {
        await tester.tap(byId('rocket.star.$n'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(sound.said.last, numberClip(n));
      }
      final notes = [for (var i = 0; i < sound.played.length; i++) if (sound.played[i].$1 == Sfx.xylophone) sound.rates[i]];
      expect(notes, hasLength(5));
      expect(notes, orderedEquals([...notes]..sort()), reason: 'a step higher each time');
      expect(labelOf(tester, 'rocket.ask'), 'Blast off!');
      expect(labelOf(tester, 'rocket.star.5'), '5, lit');
      await tester.pump(const Duration(seconds: 1));
      expect(sound.said.last, VoiceLine.rocketBlastOff);
      await tester.pump(const Duration(seconds: 1));
      await h.settle();
      expect(await toyboxRounds(h), [('rocket', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      expect(game(tester).debugDone, 0, reason: 'a new rocket on the pad');
      await tester.pump(const Duration(seconds: 10));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a star out of order wiggles and says its number; two slips ask for the next and light it; a lit star only says its number', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'rocket', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(byId('rocket.star.10'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(byId('rocket.star.10'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(sound.played.where((p) => p.$1 == Sfx.nope), isEmpty, reason: 'a lit star is not a slip');
      for (final wrong in [3, 5]) {
        await tester.tap(byId('rocket.star.$wrong'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(sound.said.last, numberClip(wrong));
      }
      expect(game(tester).debugHint, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(sound.said.last, findNumberClip(9));
      for (final n in r.countdown.skip(1)) {
        await tester.tap(byId('rocket.star.$n'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
      expect(await toyboxRounds(h), [('rocket', 2, 'helped')]);
      await tester.pump(const Duration(seconds: 10));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a long pause asks for the next star and lights it, without a slip', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'rocket', sound: sound, level: 3);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(seconds: 10));
      expect(game(tester).debugHint, isTrue);
      expect(sound.said.last, findNumberClip(r.start));
      await tester.pump(const Duration(seconds: 2));
      await h.shutdown();
    });
  });

  group('Alphabet Train', () {
    TrainGameState game(WidgetTester tester) => tester.state<TrainGameState>(find.byType(TrainGame));

    Future<void> untilAsked(WidgetTester tester) async {
      for (var i = 0; i < 120 && !game(tester).debugAsked; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game(tester).debugAsked, isTrue);
    }

    testWidgets('FR-TOY-03: the train reads its letters, asks what comes next; the right block fills the carriage and the train is read out', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'train', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      expect(r.ask, TrainAsk.next);
      await untilAsked(tester);
      expect(sound.said, [letterNameClip(r.letters[0]), letterNameClip(r.letters[1]), VoiceLine.trainNext]);
      expect(labelOf(tester, 'train.ask'), 'What comes next? ${r.letters[0]}, ${r.letters[1]}, _');
      expect(labelOf(tester, 'train.car.2'), 'Empty');
      await tester.tap(byId('train.block.${r.choices.indexOf(r.letters[2])}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, letterNameClip(r.letters[2]));
      expect(labelOf(tester, 'train.car.2'), r.letters[2]);
      expect(labelOf(tester, 'train.ask'), r.letters.join(', '));
      await tester.pump(const Duration(seconds: 4));
      expect(sound.said.reversed.take(4).toList().reversed, [...r.letters.map(letterNameClip), VoiceLine.trainGo]);
      await h.settle();
      expect(await toyboxRounds(h), [('train', 1, 'win')]);
      await tester.pump(const Duration(seconds: 6));
      expect(game(tester).debugDone, isFalse, reason: 'a new train pulls in');
      await tester.pump(const Duration(seconds: 15));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('two gaps fill left to right; a wrong block wiggles and says its letter; two slips light the right one', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'train', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.gaps, hasLength(2));
      expect(r.small, isTrue);
      await untilAsked(tester);
      expect(sound.said.last, VoiceLine.trainMissing);
      final second = r.letters[r.gaps.last];
      // The second gap's letter first: not yet.
      await tester.tap(byId('train.block.${r.choices.indexOf(second)}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, letterNameClip(second));
      final decoy = r.choices.firstWhere((c) => !r.gaps.map((g) => r.letters[g]).contains(c));
      await tester.tap(byId('train.block.${r.choices.indexOf(decoy)}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.where((p) => p.$1 == Sfx.nope), hasLength(2));
      expect(game(tester).debugHint, isTrue);
      for (final g in r.gaps) {
        await tester.tap(byId('train.block.${r.choices.indexOf(r.letters[g])}'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(game(tester).debugDone, isTrue);
      expect(labelOf(tester, 'train.car.${r.gaps.first}'), r.letters[r.gaps.first].toLowerCase());
      await h.settle();
      expect(await toyboxRounds(h), [('train', 4, 'helped')]);
      await tester.pump(const Duration(seconds: 20));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a block tapped before the question only says its letter; a long pause asks again and lights the right block', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'train', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(byId('train.block.0'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, letterNameClip(r.choices[0]));
      await untilAsked(tester);
      expect(sound.played.where((p) => p.$1 == Sfx.nope), isEmpty);
      await tester.pump(const Duration(seconds: 12));
      expect(game(tester).debugHint, isTrue);
      expect(sound.said.where((c) => c == VoiceLine.trainMissing || c == VoiceLine.trainNext), hasLength(2));
      await tester.pump(const Duration(seconds: 2));
      await h.shutdown();
    });
  });
}
