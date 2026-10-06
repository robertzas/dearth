import 'dart:io';

import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/breathe.dart';
import 'package:dearth_app/features/toybox/games/ispy.dart';
import 'package:dearth_app/features/toybox/games/letters.dart';
import 'package:dearth_app/features/toybox/games/rhymes.dart';
import 'package:dearth_app/features/toybox/games/tracing.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's voice games (SPEC FR-TOY-03), played through the Toybox on
/// the demo household. What they say is checked by clip id.
void main() {
  /// Drags a finger through the current stroke's waypoints, as she would.
  Future<void> traceStroke(WidgetTester tester) async {
    final points = <Offset>[];
    for (var i = 0; byId('trace.point.$i').evaluate().isNotEmpty; i++) {
      points.add(tester.getCenter(byId('trace.point.$i')));
    }
    final finger = await tester.startGesture(points.first);
    for (var i = 1; i < points.length; i++) {
      for (var k = 1; k <= 3; k++) {
        await finger.moveTo(Offset.lerp(points[i - 1], points[i], k / 3)!);
      }
    }
    await finger.up();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Traces every stroke of the glyph on the board.
  Future<void> traceGlyph(WidgetTester tester) async {
    for (var guard = 0; guard < 8 && !labelOf(tester, 'trace.board').endsWith('traced'); guard++) {
      await traceStroke(tester);
    }
    expect(labelOf(tester, 'trace.board'), endsWith('traced'));
  }

  test('every voice line is a bundled clip, and every clip is a line', () {
    final files = {for (final f in Directory('assets/voice').listSync().whereType<File>()) f.uri.pathSegments.last};
    expect({for (final id in kVoiceLines.keys) '$id.mp3'}.difference(files), isEmpty, reason: 'run tool/sounds/voice.py');
    expect(files.where((f) => f.endsWith('.mp3')).toSet().difference({for (final id in kVoiceLines.keys) '$id.mp3'}), isEmpty);
  });

  for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
    testWidgets('every voice game lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
      await expectGamesLayOut(tester, const [('letters', 1), ('letters', 5), ('rhymes', 3), ('ispy', 5), ('tracing', 5), ('numbers', 3), ('breathe', 3)], size: size);
    });
  }

  group('Letter Sounds', () {
    testWidgets('FR-TOY-03: she taps each letter and hears it, its sound and its picture', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'letters', sound: sound);
      final r = tester.state<LettersGameState>(find.byType(LettersGame)).debugRound;
      expect(r.mode, LetterMode.hear);
      expectNoFallbackText(byId('screen.game'));
      for (final l in r.letters) {
        await tester.tap(byId('letters.letter.${l.letter}'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(sound.said.last, letterClip(l.letter));
        expect(labelOf(tester, 'letters.letter.${l.letter}'), 'Letter ${l.letter}, heard');
      }
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
      expect(await toyboxRounds(h), [('letters', 1, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('find the letter: a wrong one says its name, the right one its sound', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'letters', sound: sound, level: 2);
      final r = tester.state<LettersGameState>(find.byType(LettersGame)).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [findLetterClip(r.answer!.letter)]);
      expect(labelOf(tester, 'letters.ask'), 'Find the letter ${r.answer!.letter}');
      final wrong = r.letters.firstWhere((l) => l != r.answer);
      await tester.tap(byId('letters.letter.${wrong.letter}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, letterNameClip(wrong.letter));
      expect(sound.played.last.$1, Sfx.nope);
      // The speaker says it again.
      await tester.tap(byId('letters.ask.again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, findLetterClip(r.answer!.letter));
      await tester.tap(byId('letters.letter.${r.answer!.letter}'));
      await h.settle();
      expect(sound.said.last, letterClip(r.answer!.letter));
      expect(await toyboxRounds(h), [('letters', 2, 'helped')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('first sound: the picture asks, a slip gets the sound as a hint', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'letters', sound: sound, level: 4);
      final r = tester.state<LettersGameState>(find.byType(LettersGame)).debugRound;
      expect(r.mode, LetterMode.firstSound);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [firstSoundClip(r.word!)]);
      expect(labelOf(tester, 'letters.ask'), 'Which letter does ${r.word!.word} start with?');
      await tester.tap(byId('letters.letter.${r.letters.firstWhere((l) => l != r.answer).letter}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, firstSoundHintClip(r.word!));
      await tester.tap(byId('letters.letter.${r.answer!.letter}'));
      await h.settle();
      expect(await toyboxRounds(h), [('letters', 4, 'helped')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
      handle.dispose();
    });
  });

  testWidgets('Rhyme Time: each picture says its word; the rhyme is cheered with both', (tester) async {
    final handle = tester.ensureSemantics();
    final sound = RecordingSound();
    final h = await openToyboxGame(tester, 'rhymes', sound: sound);
    final r = tester.state<RhymesGameState>(find.byType(RhymesGame)).debugRound;
    expect(r.choices.length, 2);
    await tester.pump(const Duration(milliseconds: 700));
    expect(sound.said, [rhymeAskClip(r.anchor)]);
    expect(labelOf(tester, 'rhymes.ask'), 'What rhymes with ${r.anchor.word}?');
    expectNoFallbackText(byId('screen.game'));
    final wrong = r.choices.firstWhere((c) => c != r.match);
    await tester.tap(byId('rhymes.choice.${wrong.word}'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sound.said.last, wrong.clip);
    await tester.tap(byId('rhymes.choice.${r.match.word}'));
    await h.settle();
    expect(sound.said.last, rhymeYesClip(r.anchor, r.match));
    expect(labelOf(tester, 'rhymes.ask'), '${r.anchor.word}, ${r.match.word}: they rhyme!');
    expect(await toyboxRounds(h), [('rhymes', 1, 'helped')]);
    await tester.pump(const Duration(seconds: 4));
    await h.shutdown();
    handle.dispose();
  });

  group('I Spy', () {
    testWidgets('something yellow: things say their names; the right one is found', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'ispy', sound: sound);
      final r = tester.state<SpyGameState>(find.byType(SpyGame)).debugRound;
      expect(r.clue, SpyClue.color);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [spyClip(SpyClue.color, r.answer.color!)]);
      expect(labelOf(tester, 'ispy.ask'), 'I spy something ${r.answer.color}');
      expectNoFallbackText(byId('screen.game'));
      await tester.tap(byId('ispy.thing.${r.answer.word}'));
      await h.settle();
      expect(sound.said.last, r.answer.clip);
      expect(labelOf(tester, 'ispy.thing.${r.answer.word}'), endsWith('found'));
      expect(await toyboxRounds(h), [('ispy', 1, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('letters at the top: something that starts with a sound, the letter in the pill', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'ispy', sound: sound, level: 5);
      final r = tester.state<SpyGameState>(find.byType(SpyGame)).debugRound;
      expect(r.clue, SpyClue.letter);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [spyClip(SpyClue.letter, r.value)]);
      final wrong = r.things.firstWhere((t) => t != r.answer);
      await tester.tap(byId('ispy.thing.${wrong.word}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, wrong.clip);
      await tester.tap(byId('ispy.thing.${r.answer.word}'));
      await h.settle();
      expect(await toyboxRounds(h), [('ispy', 5, 'helped')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Tracing', () {
    testWidgets('FR-TOY-03: a scribble draws nothing; following the dots traces the line', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'tracing');
      final glyph = tester.state<TracingGameState>(find.byType(TracingGame)).debugGlyphs.single;
      expect(kTraceLines, contains(glyph));
      expectNoFallbackText(byId('screen.game'));
      // Away from the green dot: nothing happens.
      final board = tester.getRect(find.byType(TraceBoard));
      await tester.dragFrom(board.bottomRight - const Offset(20, 20), const Offset(-200, -40));
      await tester.pump();
      expect(labelOf(tester, 'trace.board'), startsWith('Tracing $glyph: 0 of'));
      await traceGlyph(tester);
      await h.settle();
      expect(await toyboxRounds(h), [('tracing', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('her name, a letter at a time: each named, sounded out, and the whole name cheered', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'tracing', sound: sound, level: 5);
      final state = tester.state<TracingGameState>(find.byType(TracingGame));
      expect(state.debugGlyphs, ['A', 'v', 'a']);
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [VoiceLine.traceName]);
      expect(labelOf(tester, 'tracing.ask'), 'Trace your name: Ava');
      await tester.pump(afterVoice(VoiceLine.traceName) + const Duration(milliseconds: 100));
      expect(sound.said.last, letterNameClip('A'));
      for (var i = 0; i < 3; i++) {
        expect(state.debugAt, i);
        await traceGlyph(tester);
        // The next letter waits for this one's sound to finish.
        await tester.pump(afterVoice(letterClip(state.debugGlyphs[i]), atLeast: const Duration(milliseconds: 2200)) + const Duration(milliseconds: 100));
      }
      await h.settle();
      expect(sound.said, containsAllInOrder([letterClip('A'), letterNameClip('v'), letterClip('v'), letterNameClip('a'), VoiceLine.traceNameDone]));
      expect(await toyboxRounds(h), [('tracing', 5, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('Number Tracing: the number is named, traced, then counted out', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'numbers', sound: sound);
      final n = tester.state<NumbersGameState>(find.byType(NumbersGame)).debugNumber;
      expect(n, inInclusiveRange(1, 3));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [numberClip(n)]);
      expect(labelOf(tester, 'numbers.count'), 'Nothing yet');
      await traceGlyph(tester);
      // The cheer has the floor first; then each thing arrives with its number.
      expect(sound.said, [numberClip(n)]);
      await tester.pump(const Duration(milliseconds: 1250));
      expect(labelOf(tester, 'numbers.count'), '1 of $n');
      expect(sound.said.last, numberClip(1));
      await tester.pump(Duration(milliseconds: 1300 * n));
      await h.settle();
      expect(labelOf(tester, 'numbers.count'), '$n of $n');
      expect(sound.said, [numberClip(n), for (var i = 1; i <= n; i++) numberClip(i)]);
      expect(await toyboxRounds(h), [('numbers', 1, 'win')]);
      await tester.pump(const Duration(seconds: 6));
      await h.shutdown();
      handle.dispose();
    });
  });

  testWidgets('Breathing Buddy: three slow breaths with the voice, then a quiet well done', (tester) async {
    final handle = tester.ensureSemantics();
    final sound = RecordingSound();
    final h = await openToyboxGame(tester, 'breathe', sound: sound);
    final state = tester.state<BreatheGameState>(find.byType(BreatheGame));
    expect(labelOf(tester, 'breathe.ask'), 'Tap the balloon to start');
    expectNoFallbackText(byId('screen.game'));
    await tester.tap(byId('breathe.balloon'));
    await tester.pump();
    expect(sound.said, [VoiceLine.breatheStart]);
    // The welcome lasts as long as its line.
    expect(BreatheGameState.intro, greaterThan(kVoiceMs[VoiceLine.breatheStart]! / 1000));
    await tester.pump(Duration(milliseconds: (BreatheGameState.intro * 1000).round() + 400));
    expect(state.debugStep, BreathStep.breatheIn);
    expect(labelOf(tester, 'breathe.flower'), 'Flower, now');
    await tester.pump(const Duration(seconds: 4));
    expect(state.debugStep, BreathStep.breatheOut);
    expect(labelOf(tester, 'breathe.candle'), 'Candle, now');
    for (var s = 0; s < 24; s++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(state.debugStep, BreathStep.done);
    expect(sound.said, [VoiceLine.breatheStart, for (var i = 0; i < 3; i++) ...[VoiceLine.breatheIn, VoiceLine.breatheOut], VoiceLine.breatheDone]);
    expect(labelOf(tester, 'breathe.dots'), '3 of 3 breaths');
    await h.settle();
    // A calm-down isn't cheered.
    expect(byId('celebration'), findsNothing);
    expect(sound.played.map((p) => p.$1), isNot(contains(Sfx.cheer)));
    expect(await toyboxRounds(h), [('breathe', 1, 'played')]);
    await h.shutdown();
    handle.dispose();
  });
}
