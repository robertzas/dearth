import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/cookies.dart';
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
      await expectGamesLayOut(tester, const [('cookies', 1), ('cookies', 3), ('cookies', 4)], size: size);
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

    testWidgets('a wrong plate asks for more or fewer and keeps the cookies; two wrong rings show the spots; the round is a miss', (tester) async {
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
      await fill(tester, 2);
      await tester.tap(byId('cookies.bell'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, cookieFewerClip(r.want));
      expect(game(tester).debugSpots, isTrue, reason: 'after two slips the plate shows where they go');
      // Take one back off the plate: it says the new count.
      await tester.tap(byId('cookies.cookie.${r.want}'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(sound.said.last, numberClip(r.want));
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

    testWidgets('ringing an empty plate asks again and counts for nothing; a full plate shakes the jar', (tester) async {
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
      await tester.pump(const Duration(seconds: 12));
      await h.shutdown();
    });
  });
}
