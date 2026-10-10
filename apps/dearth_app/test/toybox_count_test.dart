import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/beads.dart';
import 'package:dearth_app/features/toybox/games/creaturecount.dart';
import 'package:dearth_app/features/toybox/games/fingers.dart';
import 'package:dearth_app/features/toybox/games/race.dart';
import 'package:dearth_app/features/toybox/games/share.dart';
import 'package:dearth_app/features/toybox/games/snacksnap.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's third set, six number games built on her longest-played
/// games (SPEC FR-TOY-03, Appendix B), played through the Toybox on the
/// demo household. What they say is checked by clip id.
void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
    testWidgets('every game of the third set lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
      await expectGamesLayOut(
        tester,
        const [
          ('creaturecount', 1),
          ('creaturecount', 3),
          ('creaturecount', 4),
          ('snacksnap', 1),
          ('snacksnap', 3),
          ('snacksnap', 4),
          ('fingers', 1),
          ('fingers', 3),
          ('fingers', 4),
          ('race', 1),
          ('race', 3),
          ('race', 4),
          ('beads', 1),
          ('beads', 3),
          ('beads', 4),
          ('share', 1),
          ('share', 3),
          ('share', 4),
        ],
        size: size,
      );
    });
  }

  group('Creature Count', () {
    CreatureCountGameState game(WidgetTester tester) => tester.state<CreatureCountGameState>(find.byType(CreatureCountGame));

    String askClip(CreatureCountRound r) => r.numeral ? ccountManyClip(r.asks.first.part) : ccountAskClip(r.asks.first.part, r.asks.first.n);

    /// Lets the round's ask finish, the second part's at level 3, and the
    /// once-a-session "Then make it dance!" after them.
    Future<void> intro(WidgetTester tester) async {
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(afterVoice(askClip(r)) + const Duration(milliseconds: 100));
      if (r.asks.length == 2) {
        await tester.pump(afterVoice(ccountAndClip(r.asks[1].part, r.asks[1].n)) + const Duration(milliseconds: 100));
      }
      await tester.pump(afterVoice(VoiceLine.ccountDance) + const Duration(milliseconds: 100));
    }

    /// Adds [n] of the asked part, a beat apart, as she would.
    Future<void> add(WidgetTester tester, int n) async {
      final p = game(tester).debugRound.asks.first.part;
      for (var i = 0; i < n; i++) {
        await tester.tap(byId('creaturecount.add.${p.name}'));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('FR-TOY-03: the voice asks; each tap adds a part and says the count; the right dance wins', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creaturecount', sound: sound, level: 2);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      expect(game(tester).debugGuides, isFalse, reason: 'level 2 keeps the outlines back until two slips');
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, askClip(r));
      expect(labelOf(tester, 'creaturecount.ask'), 'Give it ${countPartLabel(r.asks.first.part, r.asks.first.n)}');
      await tester.pump(afterVoice(askClip(r)) + const Duration(milliseconds: 100));
      expect(sound.said.last, VoiceLine.ccountDance, reason: 'the dance button is explained once');
      await tester.pump(afterVoice(VoiceLine.ccountDance));
      final n = r.asks.first.n;
      await add(tester, n);
      expect(game(tester).debugCounts[r.asks.first.part], n);
      expect(sound.said.sublist(sound.said.length - n), [for (var i = 1; i <= n; i++) numberClip(i)], reason: 'each part says the new count');
      expect(labelOf(tester, 'creaturecount.creature'), 'Creature: ${countPartLabel(r.asks.first.part, n)}');
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump();
      expect(labelOf(tester, 'creaturecount.ask'), 'Yay! ${countPartLabel(r.asks.first.part, n)}');
      expect(sound.said, contains(ccountYayClip(r.asks.first.part, n)));
      await tester.pump(const Duration(seconds: 3));
      expect(game(tester).debugSolved, isTrue, reason: 'the dance runs before the next round');
      await h.settle();
      expect(await toyboxRounds(h), [('creaturecount', 2, 'win')]);
      await tester.pump(const Duration(seconds: 5));
      expect(game(tester).debugSolved, isFalse, reason: 'a new creature comes');
      expect(sound.said.where((c) => c == VoiceLine.ccountDance), hasLength(1), reason: 'only once a session');
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('one too many: "Too many", a part taken off, then right is helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creaturecount', sound: sound, level: 2);
      final r = game(tester).debugRound;
      final p = r.asks.first.part, n = r.asks.first.n;
      await intro(tester);
      await add(tester, n + 1);
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, ccountFewerClip(p));
      expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(1));
      expect(game(tester).debugCounts[p], n + 1, reason: 'she fixes the creature, it isn\'t emptied');
      // Taking one off says the new count.
      await tester.tap(byId('creaturecount.part.${p.name}.$n'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, numberClip(n));
      expect(game(tester).debugCounts[p], n);
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('creaturecount', 2, 'helped')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('two slips show the outlines and make a miss; an empty creature only asks again', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creaturecount', sound: sound, level: 2);
      final r = game(tester).debugRound;
      final p = r.asks.first.part, n = r.asks.first.n;
      await intro(tester);
      // Nothing added at all: the prompt again, not a slip.
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game(tester).debugCounts.values.every((c) => c == 0), isTrue);
      expect(sound.said.where((c) => c == askClip(r)), hasLength(2));
      expect(sound.played.where((e) => e.$1 == Sfx.nope), isEmpty);
      // One too few, twice: the outlines come on. (For a want of one,
      // "too few" is no fingers at all — the empty creature — so it's one
      // too many instead.)
      if (n == 1) {
        await add(tester, 2);
        await tester.tap(byId('creaturecount.dance'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(byId('creaturecount.dance'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(game(tester).debugGuides, isTrue);
        await tester.tap(byId('creaturecount.part.${p.name}.1'));
        await tester.pump(const Duration(milliseconds: 100));
      } else {
        await add(tester, n - 1);
        await tester.tap(byId('creaturecount.dance'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(sound.said.last, ccountMoreClip(p));
        await tester.tap(byId('creaturecount.dance'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(game(tester).debugGuides, isTrue);
        await add(tester, 1);
      }
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('creaturecount', 2, 'miss')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 3 asks for two parts and needs both', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creaturecount', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.asks, hasLength(2));
      expect(r.asks[0].part, isNot(r.asks[1].part));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, ccountAskClip(r.asks[0].part, r.asks[0].n));
      await tester.pump(afterVoice(ccountAskClip(r.asks[0].part, r.asks[0].n)) + const Duration(milliseconds: 100));
      expect(sound.said.last, ccountAndClip(r.asks[1].part, r.asks[1].n), reason: 'the second part follows the first');
      expect(labelOf(tester, 'creaturecount.ask'), 'Give it ${countPartLabel(r.asks[0].part, r.asks[0].n)} and ${countPartLabel(r.asks[1].part, r.asks[1].n)}');
      await tester.pump(afterVoice(ccountAndClip(r.asks[1].part, r.asks[1].n)) + afterVoice(VoiceLine.ccountDance) + const Duration(milliseconds: 100));
      // Only the first part right: the second part's more-clip.
      await add(tester, r.asks[0].n);
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, ccountMoreClip(r.asks[1].part));
      // Both right: each is celebrated.
      for (var i = 0; i < r.asks[1].n; i++) {
        await tester.tap(byId('creaturecount.add.${r.asks[1].part.name}'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump();
      expect(labelOf(tester, 'creaturecount.ask'), 'Yay! ${countPartLabel(r.asks[0].part, r.asks[0].n)} and ${countPartLabel(r.asks[1].part, r.asks[1].n)}');
      expect(sound.said, contains(ccountYayClip(r.asks[0].part, r.asks[0].n)));
      expect(sound.said, contains(ccountAndClip(r.asks[1].part, r.asks[1].n)));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('creaturecount', 3, 'helped')], reason: 'the wrong first dance is one slip');
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 4 says "this many" and shows the numeral', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creaturecount', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.numeral, isTrue);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, ccountManyClip(r.asks.first.part));
      final n = r.asks.first.n;
      expect(labelOf(tester, 'creaturecount.ask'), 'Give it this many ${kCountPartWords[r.asks.first.part]!.$2}: $n');
      await intro(tester);
      await add(tester, n);
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('creaturecount', 4, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a full part button wiggles and adds nothing', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creaturecount', sound: sound, level: 2);
      final r = game(tester).debugRound;
      final p = r.asks.first.part, n = r.asks.first.n;
      await intro(tester);
      await add(tester, n);
      await add(tester, kCountPartMax[p]! - n);
      expect(game(tester).debugCounts[p], kCountPartMax[p]);
      await tester.tap(byId('creaturecount.add.${p.name}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game(tester).debugCounts[p], kCountPartMax[p], reason: 'nothing was added');
      expect(sound.played.where((e) => e.$1 == Sfx.boing), hasLength(1));
      expect(sound.played.where((e) => e.$1 == Sfx.nope), isEmpty, reason: 'not a slip');
      // Take the extras off and dance: still a clean win.
      for (var i = n; i < kCountPartMax[p]!; i++) {
        await tester.tap(byId('creaturecount.part.${p.name}.0'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game(tester).debugCounts[p], n);
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('creaturecount', 2, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Snack Snap', () {
    SnackSnapGameState game(WidgetTester tester) => tester.state<SnackSnapGameState>(find.byType(SnackSnapGame));

    testWidgets('FR-TOY-03: the voice asks for treats; the right plate feeds the monster and wins', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'snacksnap', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, snackWantClip(r.want));
      expect(labelOf(tester, 'snacksnap.ask'), 'Snack: ${r.want} treat${r.want == 1 ? '' : 's'}');
      await tester.tap(byId('snacksnap.plate.${r.answer}'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(sound.said, contains(snackYumClip(r.want)));
      expect(sound.played.where((e) => e.$1 == Sfx.munch), hasLength(r.want), reason: 'one munch a treat');
      expect(labelOf(tester, 'snacksnap.ask'), 'Yum! ${r.want} treat${r.want == 1 ? '' : 's'}');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('snacksnap', 1, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a wrong plate says its own amount; two slips light the right one', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'snacksnap', sound: sound, level: 2);
      final r = game(tester).debugRound;
      final wrong = [for (var i = 0; i < r.plates.length; i++) if (i != r.answer) i];
      expect(wrong, hasLength(2));
      await tester.pump(const Duration(milliseconds: 700));
      for (final i in wrong) {
        await tester.tap(byId('snacksnap.plate.$i'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sound.said, containsAllInOrder([for (final i in wrong) snackThatsClip(r.plates[i].n)]));
      expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(2));
      expect(game(tester).debugHint, isTrue, reason: 'the right plate glows after two slips');
      // A tried plate is done for the round: tapping it again is nothing.
      final said = sound.said.length;
      await tester.tap(byId('snacksnap.plate.${wrong.first}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.length, said);
      await tester.tap(byId('snacksnap.plate.${r.answer}'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('snacksnap', 2, 'miss')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 4: "Quick, look!", then the plates cover; she chooses from memory', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'snacksnap', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.flash, isTrue);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, VoiceLine.snackLook);
      await tester.pump(afterVoice(VoiceLine.snackLook) + const Duration(milliseconds: 100));
      expect(sound.said.last, snackWantClip(r.want));
      await tester.pump(const Duration(milliseconds: 2100));
      expect(game(tester).debugCovered, isTrue);
      for (var i = 0; i < r.plates.length; i++) {
        expect(labelOf(tester, 'snacksnap.plate.$i'), 'Covered plate');
      }
      await tester.tap(byId('snacksnap.plate.${r.answer}'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('snacksnap', 4, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a peek at the covered plates can\'t be a clean win', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'snacksnap', sound: sound, level: 4);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(afterVoice(VoiceLine.snackLook) + const Duration(milliseconds: 100));
      await tester.pump(afterVoice(snackWantClip(r.want)) + const Duration(milliseconds: 2100));
      expect(game(tester).debugCovered, isTrue);
      await tester.tap(byId('snacksnap.ask.again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game(tester).debugCovered, isFalse, reason: 'the peek lifts the covers');
      await tester.tap(byId('snacksnap.plate.${r.answer}'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('snacksnap', 4, 'helped')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Finger Count', () {
    FingerGameState game(WidgetTester tester) => tester.state<FingerGameState>(find.byType(FingerGame));

    /// Lets the ask (and the once-a-session high-five line) finish.
    Future<void> intro(WidgetTester tester) async {
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      if (r.mode != FingerMode.read) {
        await tester.pump(afterVoice(fingersShowClip(r.want)) + const Duration(milliseconds: 100));
        await tester.pump(afterVoice(VoiceLine.fingersHighFive) + const Duration(milliseconds: 100));
      }
    }

    testWidgets('FR-TOY-03: the voice asks; palm taps raise fingers in order and say the counts; the high five wins', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'fingers', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, fingersShowClip(r.want));
      expect(labelOf(tester, 'fingers.ask'), 'Show ${r.want}');
      await tester.pump(afterVoice(fingersShowClip(r.want)) + const Duration(milliseconds: 100));
      expect(sound.said.last, VoiceLine.fingersHighFive, reason: 'the high five is explained once a session');
      await tester.pump(afterVoice(VoiceLine.fingersHighFive));
      final n = r.want;
      for (var i = 1; i <= n; i++) {
        await tester.tap(byId('fingers.palm.right'));
        await tester.pump(const Duration(milliseconds: 120));
        expect(labelOf(tester, 'fingers.hand.right'), 'Right hand: $i ${i == 1 ? 'finger' : 'fingers'} up');
      }
      expect(labelOf(tester, 'fingers.finger.right.0'), 'Thumb, up', reason: 'the thumb counts first');
      expect(game(tester).debugUp, n);
      expect(sound.said.sublist(sound.said.length - n), [for (var i = 1; i <= n; i++) numberClip(i)]);
      await tester.tap(byId('fingers.done'));
      await tester.pump();
      expect(labelOf(tester, 'fingers.ask'), 'Yay! $n ${n == 1 ? 'finger' : 'fingers'}');
      expect(sound.said, contains(fingersYayClip(n)));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('fingers', 1, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('toggles say the new total; too many is a slip, then fixing it is helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'fingers', sound: sound, level: 2);
      final r = game(tester).debugRound;
      final n = r.want;
      await intro(tester);
      for (var i = 0; i < n; i++) {
        await tester.tap(byId('fingers.finger.right.$i'));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(game(tester).debugUp, n);
      // Toggling a finger down says the new total.
      await tester.tap(byId('fingers.finger.right.0'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(game(tester).debugUp, n - 1);
      expect(sound.said.last, numberClip(n - 1));
      await tester.tap(byId('fingers.finger.right.0'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(game(tester).debugUp, n);
      if (n < 5) {
        // One too many, then the high five: "Too many fingers!".
        await tester.tap(byId('fingers.finger.right.$n'));
        await tester.pump(const Duration(milliseconds: 120));
        expect(game(tester).debugUp, n + 1);
        await tester.tap(byId('fingers.done'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(sound.said.last, VoiceLine.fingersFewer);
        expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(1));
        await tester.tap(byId('fingers.finger.right.$n'));
        await tester.pump(const Duration(milliseconds: 120));
      } else {
        // The full hand can only be too few: let one down first.
        await tester.tap(byId('fingers.finger.right.0'));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(byId('fingers.done'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(sound.said.last, VoiceLine.fingersMore);
        expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(1));
        await tester.tap(byId('fingers.finger.right.0'));
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.tap(byId('fingers.done'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('fingers', 2, 'helped')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the left palm raises a whole hand; the make-clip names the five and some more', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'fingers', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.want, greaterThan(5));
      await intro(tester);
      await tester.tap(byId('fingers.palm.left'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(sound.said.last, VoiceLine.fingersFive);
      expect(game(tester).debugUp, 5);
      expect(labelOf(tester, 'fingers.hand.left'), 'Left hand: 5 fingers up');
      for (var i = 0; i < r.want - 5; i++) {
        await tester.tap(byId('fingers.finger.right.$i'));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(game(tester).debugUp, r.want);
      await tester.tap(byId('fingers.done'));
      await tester.pump();
      expect(labelOf(tester, 'fingers.ask'), 'Yay! ${r.want} fingers');
      expect(sound.said, contains(fingersYayClip(r.want)));
      await tester.pump(afterVoice(fingersYayClip(r.want)) + const Duration(milliseconds: 100));
      expect(sound.said, contains(fingersMakeClip(r.want)), reason: 'five and some more make it');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('fingers', 3, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('reading the hand: a wrong numeral says itself, then the right one is helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'fingers', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.mode, FingerMode.read);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, VoiceLine.fingersWhich);
      expect(labelOf(tester, 'fingers.ask'), 'How many fingers?');
      expect(game(tester).debugUp, r.want, reason: 'the hand is already up; she reads it');
      final wrong = r.choices.where((c) => c != r.want).first;
      await tester.tap(byId('fingers.choice.$wrong'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, numberClip(wrong));
      expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(1));
      await tester.tap(byId('fingers.choice.${r.want}'));
      await tester.pump();
      expect(labelOf(tester, 'fingers.ask'), 'Yay! ${r.want} finger${r.want == 1 ? '' : 's'}');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('fingers', 4, 'helped')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Animal Race', () {
    RaceGameState game(WidgetTester tester) => tester.state<RaceGameState>(find.byType(RaceGame));

    /// Runs the race out in frames: ticker-driven games crawl in tests.
    Future<void> run(RaceGameState s, WidgetTester tester) async {
      for (var guard = 0; s.debugRacing && guard < 600; guard++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(s.debugRacing, isFalse);
    }

    testWidgets('FR-TOY-03: the race runs, then the right animal is ribboned', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'race', sound: sound, level: 2);
      final s = game(tester);
      final r = s.debugRound;
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, VoiceLine.raceGo);
      expect(labelOf(tester, 'race.animal.0'), '${_cap(kRacers[r.racers[0]].$2)}, racing');
      await run(s, tester);
      final want = r.asks.single;
      expect(sound.said, contains(raceAskClip(want)));
      expect(labelOf(tester, 'race.ask'), 'Who came ${ordinal(want)}?');
      final lane = r.places.indexOf(want);
      final place = r.places[lane];
      await tester.tap(byId('race.animal.$lane'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(sound.said, contains(racePlaceClip(place)));
      expect(s.debugRibbons[lane], place);
      expect(labelOf(tester, 'race.animal.$lane'), '${_cap(kRacers[r.racers[lane]].$2)}, came ${ordinal(place)}');
      expect(labelOf(tester, 'race.ask'), 'Yes! ${ordinalWord(place)}');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('race', 2, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a wrong animal says its own place; two slips light the winner', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'race', sound: sound, level: 2);
      final s = game(tester);
      final r = s.debugRound;
      final want = r.asks.single;
      await run(s, tester);
      final right = r.places.indexOf(want);
      final wrong = [for (var l = 0; l < r.lanes; l++) if (l != right) l];
      for (final lane in wrong) {
        await tester.tap(byId('race.animal.$lane'));
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(sound.said, containsAllInOrder([for (final lane in wrong) raceCameClip(r.places[lane])]));
      expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(r.lanes - 1));
      expect(s.debugHint, isTrue);
      await tester.tap(byId('race.animal.$right'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('race', 2, 'miss')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the podium: all five in order is one round; a slip in between is helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'race', sound: sound, level: 4);
      final s = game(tester);
      final r = s.debugRound;
      expect(r.asks, [1, 2, 3, 4, 5]);
      await run(s, tester);
      // One wrong tap while the first place is asked.
      final notFirst = [for (var l = 0; l < r.lanes; l++) if (l != r.places.indexOf(1)) l];
      await tester.tap(byId('race.animal.${notFirst.first}'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(sound.said.last, raceCameClip(r.places[notFirst.first]));
      // Then the five, in order.
      for (final want in r.asks) {
        final lane = r.places.indexOf(want);
        await tester.tap(byId('race.animal.$lane'));
        await tester.pump(afterVoice(racePlaceClip(want)) + const Duration(milliseconds: 100));
      }
      expect(s.debugSolved, isTrue);
      expect(s.debugRibbons.length, 5);
      expect(labelOf(tester, 'race.ask'), 'Yes! All in order');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('race', 4, 'helped')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Bead Slider', () {
    BeadGameState game(WidgetTester tester) => tester.state<BeadGameState>(find.byType(BeadGame));

    /// Lets the ask (and the once-a-session bell line) finish.
    Future<void> intro(WidgetTester tester) async {
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      if (!r.read) {
        await tester.pump(afterVoice(beadsShowClip(r.want)) + const Duration(milliseconds: 100));
        await tester.pump(afterVoice(VoiceLine.cookiesBell) + const Duration(milliseconds: 100));
      }
    }

    testWidgets('FR-TOY-03: one tap slides the beads across; the bell names the structure', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'beads', sound: sound, level: 2);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, beadsShowClip(r.want));
      expect(labelOf(tester, 'beads.ask'), 'Show ${r.want}');
      await tester.pump(afterVoice(beadsShowClip(r.want)) + const Duration(milliseconds: 100));
      expect(sound.said.last, VoiceLine.cookiesBell, reason: 'the bell is explained once a session');
      await tester.pump(afterVoice(VoiceLine.cookiesBell));
      await tester.tap(byId('beads.bead.0.${r.want - 1}'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(game(tester).debugLeft[0], r.want, reason: 'one tap slides everything left of it across');
      expect(sound.said.last, numberClip(r.want));
      expect(labelOf(tester, 'beads.row.0'), 'Top row: ${r.want} ${r.want == 1 ? 'bead' : 'beads'} across');
      await tester.tap(byId('beads.bell'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.last, beadsYayClip(r.want));
      expect(labelOf(tester, 'beads.ask'), 'Yay! ${r.want}');
      expect(sound.played.map((e) => e.$1), contains(Sfx.xylophone), reason: 'the rack chimes');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('beads', 2, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a tap on a bead already across slides them back', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'beads', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await intro(tester);
      await tester.tap(byId('beads.bead.0.${r.want - 1}'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(game(tester).debugTotal, r.want);
      await tester.tap(byId('beads.bead.0.0'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(game(tester).debugLeft[0], 0, reason: 'the bead and everything right of it slide back');
      expect(sound.said.last, numberClip(0));
      await tester.tap(byId('beads.bead.0.${r.want - 1}'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(byId('beads.bell'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('beads', 2, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('wrong totals ask for more or fewer; two slips mark where to stop', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'beads', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await intro(tester);
      await tester.tap(byId('beads.bead.0.${r.want - 2}'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(byId('beads.bell'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(sound.said.last, VoiceLine.beadsMore);
      expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(1));
      await tester.tap(byId('beads.bell'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(game(tester).debugHint, isTrue);
      await tester.tap(byId('beads.bead.0.${r.want - 1}'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(byId('beads.bell'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('beads', 2, 'miss')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('two rows: ten and some more, as the rack is read', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'beads', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.rows, 2);
      await intro(tester);
      await tester.tap(byId('beads.bead.0.9'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(game(tester).debugLeft[0], 10);
      expect(labelOf(tester, 'beads.row.0'), 'Top row: 10 beads across');
      await tester.tap(byId('beads.bead.1.${r.want - 11}'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(game(tester).debugTotal, r.want);
      await tester.tap(byId('beads.bell'));
      await tester.pump();
      expect(sound.said.last, beadsYayClip(r.want));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('beads', 3, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('reading the rack: the beads are across, she picks the number', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'beads', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.read, isTrue);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, VoiceLine.beadsWhich);
      expect(labelOf(tester, 'beads.ask'), 'How many beads?');
      expect(game(tester).debugTotal, r.want, reason: 'the beads are already across; she reads them');
      final wrong = r.choices.where((c) => c != r.want).first;
      await tester.tap(byId('beads.choice.$wrong'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, numberClip(wrong));
      await tester.tap(byId('beads.choice.${r.want}'));
      await tester.pump();
      expect(labelOf(tester, 'beads.ask'), 'Yay! ${r.want}');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('beads', 4, 'helped')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Fair Share', () {
    ShareGameState game(WidgetTester tester) => tester.state<ShareGameState>(find.byType(ShareGame));

    /// Lets the ask (and the once-a-session bell line) finish.
    Future<void> intro(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(afterVoice(VoiceLine.shareAsk) + const Duration(milliseconds: 100));
      await tester.pump(afterVoice(VoiceLine.cookiesBell) + const Duration(milliseconds: 100));
    }

    /// A tap on the plate's rim, below its cupcakes: the centre can be
    /// covered by a cupcake of its own.
    Future<void> give(WidgetTester tester, int i) async {
      final rect = tester.getRect(byId('share.plate.$i'));
      await tester.tapAt(rect.bottomCenter - Offset(0, rect.height * 0.12));
      await tester.pump(const Duration(milliseconds: 350));
    }

    testWidgets('FR-TOY-03: share them evenly and the bell finds it fair', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'share', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.first, VoiceLine.shareAsk);
      expect(labelOf(tester, 'share.ask'), 'Share ${r.treats} cupcakes');
      await tester.pump(afterVoice(VoiceLine.shareAsk) + const Duration(milliseconds: 100));
      expect(sound.said.last, VoiceLine.cookiesBell, reason: 'the bell is explained once a session');
      await tester.pump(afterVoice(VoiceLine.cookiesBell));
      for (var k = 0; k < r.treats; k++) {
        await give(tester, k % r.monsters);
      }
      expect(game(tester).debugPlates, [for (var i = 0; i < r.monsters; i++) r.each]);
      expect(game(tester).debugTray, r.left);
      expect(sound.said, contains(numberClip(1)));
      expect(labelOf(tester, 'share.plate.0'), 'Plate 1: ${r.each} cupcake${r.each == 1 ? '' : 's'}');
      expect(labelOf(tester, 'share.tray'), 'Tray: ${r.left} cupcake${r.left == 1 ? '' : 's'}');
      // The tray is empty: another give is a boing, not a slip.
      await give(tester, 0);
      expect(game(tester).debugPlates[0], r.each);
      expect(sound.played.where((e) => e.$1 == Sfx.boing), hasLength(1));
      await tester.tap(byId('share.bell'));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(sound.said.last, shareEachClip(r.each));
      expect(labelOf(tester, 'share.ask'), '${r.each} each!');
      expect(sound.played.where((e) => e.$1 == Sfx.munch), hasLength(r.each * r.monsters), reason: 'everyone eats');
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('share', 1, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('unequal: the one with fewest complains, and fixing it is helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'share', sound: sound, level: 1);
      final r = game(tester).debugRound;
      await intro(tester);
      for (var k = 0; k < r.treats; k++) {
        await give(tester, k % r.monsters);
      }
      // Move one from plate 1 to plate 0: not fair.
      await tester.tap(byId('share.cupcake.1.0'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(game(tester).debugPlates[1], r.each - 1);
      await give(tester, 0);
      await tester.tap(byId('share.bell'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(sound.said.last, VoiceLine.shareFewer);
      expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(1));
      expect(game(tester).debugPlates, isNot(equals([for (var i = 0; i < r.monsters; i++) r.each])), reason: 'the cupcakes stay to fix');
      // Put it back: one each again, and the bell finds it fair.
      await tester.tap(byId('share.cupcake.0.0'));
      await tester.pump(const Duration(milliseconds: 350));
      await give(tester, 1);
      await tester.tap(byId('share.bell'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('share', 1, 'helped')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('equal plates but the tray still holds more to share', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'share', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await intro(tester);
      for (var k = 0; k < 2; k++) {
        await give(tester, k % r.monsters);
      }
      expect(game(tester).debugTray, r.treats - 2, reason: 'most of the cupcakes still on the tray');
      await tester.tap(byId('share.bell'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(sound.said.last, VoiceLine.shareMore);
      expect(sound.played.where((e) => e.$1 == Sfx.nope), hasLength(1));
      // Ring again: two slips, and the plates show their fair share.
      await tester.tap(byId('share.bell'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(game(tester).debugHint, isTrue);
      // Finish the sharing: fair, but a miss after two slips.
      for (var k = 2; k < r.treats; k++) {
        await give(tester, k % r.monsters);
      }
      await tester.tap(byId('share.bell'));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('share', 2, 'miss')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the top level leaves one over, for later', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'share', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.left, 1);
      await intro(tester);
      for (var k = 0; k < r.treats - 1; k++) {
        await give(tester, k % r.monsters);
      }
      expect(game(tester).debugTray, 1);
      await tester.tap(byId('share.bell'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(labelOf(tester, 'share.ask'), '${r.each} each, 1 left over');
      expect(sound.said, contains(shareEachClip(r.each)));
      await tester.pump(afterVoice(shareEachClip(r.each)) + const Duration(milliseconds: 100));
      expect(sound.said.last, VoiceLine.shareLeft);
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(await toyboxRounds(h), [('share', 4, 'win')]);
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
      handle.dispose();
    });
  });
}

String _cap(String s) => '${s[0].toUpperCase()}${s.substring(1)}';
