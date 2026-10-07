import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../game_host.dart';
import 'game_widgets.dart';

/// Letters in the Montessori colors: vowels blue, consonants red.
const Color kVowelColor = Color(0xFF2F6FD6);
const Color kConsonantColor = Color(0xFFE0414F);

Color letterColor(String letter) => 'AEIOU'.contains(letter.toUpperCase()) ? kVowelColor : kConsonantColor;

/// Draws a [Glyph] the way the Toybox writes: ball-and-stick strokes with
/// round ends, the same shapes she traces.
class GlyphPainter extends CustomPainter {
  const GlyphPainter(this.glyph, {required this.color, this.weight = 1.3, this.frameTop, this.frameBottom});
  final Glyph glyph;
  final Color color;

  /// Stroke width, in glyph units (capitals are 10 tall).
  final double weight;

  /// The band the glyph sits in, in glyph units: its own ink by default; a
  /// shared band puts letters on one baseline.
  final double? frameTop, frameBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (frameTop ?? glyph.top) - weight / 2;
    final bottom = (frameBottom ?? glyph.bottom) + weight / 2;
    final unit = size.height / (bottom - top);
    final left = (size.width - glyph.width * unit) / 2;
    Offset at(math.Point<double> p) => Offset(left + p.x * unit, (p.y - top) * unit);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in glyph.strokes) {
      if (s.length == 1) {
        canvas.drawCircle(at(s.first), weight * unit * 0.62, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(at(s.first).dx, at(s.first).dy);
      for (final p in s.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(GlyphPainter old) => old.glyph != glyph || old.color != color || old.weight != weight || old.frameTop != frameTop || old.frameBottom != frameBottom;
}

/// A letter or digit, [height] tall including its band.
class GlyphView extends StatelessWidget {
  const GlyphView(this.char, {super.key, required this.height, required this.color, this.weight = 1.3, this.frameTop, this.frameBottom});
  final String char;
  final double height;
  final Color color;
  final double weight;
  final double? frameTop, frameBottom;

  @override
  Widget build(BuildContext context) {
    final g = glyphFor(char);
    final band = (frameBottom ?? g.bottom) - (frameTop ?? g.top) + weight;
    final unit = height / band;
    return CustomPaint(
      size: Size((g.width + weight) * unit, height),
      painter: GlyphPainter(g, color: color, weight: weight, frameTop: frameTop, frameBottom: frameBottom),
    );
  }
}

/// A letter the way alphabet charts show it, capital and small on one
/// baseline: "Bb".
class LetterPair extends StatelessWidget {
  const LetterPair(this.letter, {super.key, required this.height});
  final String letter;

  /// From the top of the capital to the bottom of a descender.
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = letterColor(letter);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphView(letter.toUpperCase(), height: height, color: color, frameTop: 0, frameBottom: 14),
        SizedBox(width: height * 0.08),
        GlyphView(letter.toLowerCase(), height: height, color: color, frameTop: 0, frameBottom: 14),
      ],
    );
  }
}

/// A word in the Toybox's print: every letter on one shared band, so a
/// name's capital and small letters sit on one line, as Sight Words' signs
/// print them.
class PrintedWord extends StatelessWidget {
  const PrintedWord(this.word, {super.key, required this.height, this.color = const Color(0xFF2B2440)});
  final String word;

  /// The band's height: a capital's.
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ch in word.split(''))
            Padding(padding: EdgeInsets.symmetric(horizontal: height * 0.025), child: GlyphView(ch, height: height, color: color, frameTop: 0, frameBottom: 14)),
        ],
      );
}

/// What a voice game asks, as a picture pill (she can't read; the label is
/// for grown-ups' screen readers and tests), with a speaker beside it that
/// says it again.
class PromptPill extends StatelessWidget {
  const PromptPill({super.key, required this.id, required this.label, required this.children, this.onSayAgain});
  final String id;
  final String label;
  final List<Widget> children;
  final VoidCallback? onSayAgain;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tid(id, Semantics(label: label, excludeSemantics: true, child: GamePill(children: children))),
        if (onSayAgain != null) ...[
          SizedBox(width: t.space.sm),
          DPressable(
            id: '$id.again',
            semanticLabel: 'Say it again',
            excludeSemantics: true,
            onTap: onSayAgain,
            borderRadius: t.radius.pill,
            child: Container(
              width: 68 * t.scale,
              height: 68 * t.scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle, boxShadow: t.elevation.e1),
              child: DEmoji('🔊', size: 34 * t.scale),
            ),
          ),
        ],
      ],
    );
  }
}

/// The pill at the top of a game, centred under the home button's row.
class TopPrompt extends StatelessWidget {
  const TopPrompt({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Positioned(top: t.space.md, left: 0, right: 0, child: SafeArea(child: Center(child: child)));
  }
}

/// Tiles in rows of [per], centred: predictable where a Wrap would pack
/// three and leave one.
class TileRows extends StatelessWidget {
  const TileRows({super.key, required this.per, required this.children});
  final int per;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i += per) Row(mainAxisSize: MainAxisSize.min, children: children.sublist(i, math.min(i + per, children.length))),
        ],
      );
}

/// The picture a question is about (a word to rhyme with, a first sound to
/// hear), big and round above the choices. A tap asks again.
class SubjectCard extends StatelessWidget {
  const SubjectCard({super.key, required this.id, required this.word, required this.size, required this.onTap, this.hops = 0});
  final String id;
  final PictureWord word;
  final double size;
  final VoidCallback onTap;
  final int hops;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DPressable(
      id: id,
      semanticLabel: word.word,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Hop(
        count: hops,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE3DCF5), width: 4), boxShadow: t.elevation.e1),
          child: DEmoji(word.emoji, size: size * 0.6),
        ),
      ),
    );
  }
}
