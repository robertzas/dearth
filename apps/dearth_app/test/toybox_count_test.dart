import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/creaturecount.dart';
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
      await expectGamesLayOut(tester, const [('creaturecount', 1), ('creaturecount', 3), ('creaturecount', 4), ('snacksnap', 1), ('snacksnap', 3), ('snacksnap', 4)], size: size);
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
      // One too few, twice: the outlines come on.
      await add(tester, n - 1);
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, ccountMoreClip(p));
      await tester.tap(byId('creaturecount.dance'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game(tester).debugGuides, isTrue);
      await add(tester, 1);
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
}
