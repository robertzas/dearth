import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/grown_up.dart';
import '../../app/router.dart';
import '../../core/data/household.dart';
import '../../shared/face_photo.dart';
import 'game_host.dart';
import 'games/compare.dart';
import 'games/creature.dart';
import 'games/dots_pictures.dart';
import 'games/registry.dart';
import 'toybox_data.dart';

/// Each game's tile color: the launcher is read by picture and color, so no
/// two games share a hue — a kid finds "the sunshine one" before she can read
/// "Counting Garden". A test keeps one entry per catalog game.
const Map<String, Color> kGameHues = {
  'bubbles': Color(0xFF4FB3F6),
  'paint': Color(0xFFF06BA8),
  'coloring': Color(0xFFFF9F43),
  'farm': Color(0xFF5CC46B),
  'shapes': Color(0xFF9C6ADE),
  'music': Color(0xFF2EC4B6),
  'jigsaw': Color(0xFF4C7BF4),
  'memory': Color(0xFF7067E8),
  'monster': Color(0xFFEF6B5C),
  'counting': Color(0xFFF5B800),
  'patterns': Color(0xFF19A7CE),
  'oddone': Color(0xFFEC6A96),
  'shadows': Color(0xFF7D8CA3),
  'sizes': Color(0xFF58A55C),
  'mazes': Color(0xFFE08632),
  'stories': Color(0xFFB23A68),
  'sudoku': Color(0xFF5058A8),
  'differences': Color(0xFF97B43C),
  'letters': Color(0xFFE8445C),
  'rhymes': Color(0xFFA64AC9),
  'ispy': Color(0xFF2D9BF0),
  'tracing': Color(0xFFFFAE42),
  'numbers': Color(0xFF2F6FE0),
  'breathe': Color(0xFF57C4AD),
  'creature': Color(0xFF0E9594),
  'dots': Color(0xFF4441A9),
  'biglittle': Color(0xFFC63A6B),
  'hop': Color(0xFF43A94C),
  'spell': Color(0xFF845EC2),
  'hear': Color(0xFFEE7B30),
  'sight': Color(0xFFDE4B33),
  'balance': Color(0xFFFFD23F),
  'compare': Color(0xFF2FA67A),
  'zoo': Color(0xFFA0522D),
  'tally': Color(0xFF2F5D50),
  'hundred': Color(0xFF1E6091),
  'freeze': Color(0xFFE040FB),
  'sequencer': Color(0xFF3A0CA3),
  'dressup': Color(0xFF6D597A),
  'whosthat': Color(0xFFFF8FAB),
  'storytime': Color(0xFFE0A458),
};

/// The Toybox (SPEC §10.8, FR-TOY-01): big picture tiles of the games that
/// suit the kid playing, "new!" on the ones they haven't opened, the time
/// left today, and a grown-up corner for the settings. A kid surface:
/// nothing on it changes or deletes anything (AGENTS.md rule 9).
class ToyboxScreen extends ConsumerWidget {
  const ToyboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final kid = ref.watch(toyboxKidProvider);
    final kids = ref.watch(kidsProvider);
    if (kid == null) {
      return screenTid(
        'screen.toybox',
        const Center(
          child: DEmptyState(id: 'toybox.nokids', emoji: '🧸', title: 'No kids yet', message: 'Add a kid in Settings → People, and their Toybox opens here.'),
        ),
      );
    }
    final time = ref.watch(toyboxTimeProvider(kid.id));
    return screenTid(
      'screen.toybox',
      Padding(
        padding: EdgeInsets.fromLTRB(t.pageMargin, t.pageMargin, t.pageMargin, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProfileAvatar(kid, size: 56 * t.scale),
                SizedBox(width: t.space.md),
                Expanded(child: tid('toybox.title', Text('${kid.name}’s Toybox', style: t.text.h2, maxLines: 1, overflow: TextOverflow.ellipsis))),
                if (time.minutesLeft != null && time.open) ...[
                  tid('toybox.timeleft', _Chip(text: '⏳ ${time.minutesLeft} min')),
                  SizedBox(width: t.space.sm),
                ],
                const _GrownUpCorner(),
              ],
            ),
            if (kids.length > 1) ...[
              SizedBox(height: t.space.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: DSegmented<String>(
                  idPrefix: 'toybox.kid',
                  options: [for (final k in kids) (k.id, k.name)],
                  value: kid.id,
                  onChanged: (id) => chooseToyboxKid(ref, id),
                ),
              ),
            ],
            SizedBox(height: t.gutter),
            Expanded(child: time.open ? _Grid(kid: kid) : _Sleeping(why: time.why)),
          ],
        ),
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.kid});
  final Profile kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    // Catalog entries without a playfield yet stay hidden until they land.
    final games = [for (final g in ref.watch(kidGamesProvider(kid.id))) if (kGameBuilders.containsKey(g.id)) g];
    final seen = ref.watch(seenGamesProvider(kid.id)).value;
    if (games.isEmpty) {
      return const DEmptyState(id: 'toybox.empty', emoji: '🧸', title: 'All the games are off', message: 'A grown-up can switch them on in the Toybox settings.');
    }
    return LayoutBuilder(builder: (context, box) {
      final gap = t.space.md;
      // Square tiles about 190 dp (scaled) across, six at most: six on a
      // landscape wall, four on a portrait one, two on a phone.
      final cols = (box.maxWidth / (190 * t.scale)).floor().clamp(2, 6);
      // A lazy grid (SPEC §12.3): only the visible tiles build and paint, and
      // each gets its own repaint boundary, so scrolling doesn't re-paint the
      // whole launcher on the frame's GPU (a Wrap in a SingleChildScrollView
      // measured 14 fps there).
      return GridView.builder(
        padding: EdgeInsets.only(bottom: t.pageMargin),
        addAutomaticKeepAlives: false,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
        ),
        itemCount: games.length,
        itemBuilder: (context, i) {
          final g = games[i];
          return _Tile(game: g, kid: kid, size: (box.maxWidth - gap * (cols - 1)) / cols, isNew: seen != null && !seen.contains(g.id));
        },
      );
    });
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.game, required this.kid, required this.size, required this.isNew});
  final GameInfo game;
  final Profile kid;
  final double size;
  final bool isNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final hue = kGameHues[game.id] ?? t.colors.accent;
    final level = ref.watch(gameLevelProvider((kid.id, game.id)));
    final tile = DPressable(
      id: 'toybox.game.${game.id}',
      semanticLabel: game.title,
      excludeSemantics: true,
      borderRadius: BorderRadius.circular(t.radius.l),
      // No press fade/scale: opening the game is the feedback, and an
      // opacity layer at every scroll start is what made dragging stutter
      // on the frame (AGENTS rule 8).
      pressFeedback: false,
      onTap: () => openGame(context, ref, game, kid),
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            // Solid, not a gradient: one flat fill per tile. The two-color
            // gradient was the launcher's biggest fill cost on the frame's
            // GPU (SPEC §12.3, AGENTS rule 8), and the white title and dots
            // already sat on the `hue` end, so contrast is unchanged.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.l),
              color: hue,
              boxShadow: t.elevation.e1,
            ),
          child: Stack(
            children: [
              Center(child: Padding(padding: EdgeInsets.only(bottom: size * 0.14), child: GameIcon(game, size: size * 0.44))),
              Positioned(
                left: t.space.sm,
                right: t.space.sm,
                bottom: t.space.sm,
                child: Column(
                  children: [
                    // The title keeps its size relative to the tile (26 on a
                    // 310 tile), and a long one shrinks a little more rather
                    // than lose its end ("Letter & Name Tracing").
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        game.title,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: t.text.title.copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: math.min(t.text.title.fontSize!, size * 0.084)),
                      ),
                    ),
                    SizedBox(height: t.space.xxs),
                    // The level, for grown-ups: small dots, no numbers.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= game.levels; i++)
                          Container(
                            width: 7 * t.scale,
                            height: 7 * t.scale,
                            margin: EdgeInsets.symmetric(horizontal: 2 * t.scale),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: i <= level ? 0.95 : 0.35)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!isNew) return tile;
    // Beside the tile's button, not inside it: the button excludes its
    // children's semantics, and the web would never see the sparkle.
    return Stack(
      children: [
        tile,
        Positioned(
          top: t.space.sm,
          right: t.space.sm,
          child: IgnorePointer(child: tid('toybox.new.${game.id}', const _Chip(text: '✨ New!', dense: true))),
        ),
      ],
    );
  }
}

/// A game's picture: its emoji, or for Bubble Pop painted bubbles (the
/// bubble emoji is newer than Android 10, so the kitchen frame can't draw it),
/// for Build-a-Creature one of its creatures, and for Dot-to-Dot a star half
/// joined (a plain star reads as a reward, not a game), and for Who Has
/// More? one of its buses.
class GameIcon extends StatelessWidget {
  const GameIcon(this.game, {super.key, required this.size});
  final GameInfo game;
  final double size;

  static const _creature = Creature({CreaturePart.body: 0, CreaturePart.face: 0, CreaturePart.top: 2, CreaturePart.legs: 1, CreaturePart.arms: 1}, 2);

  @override
  Widget build(BuildContext context) => switch (game.id) {
        'bubbles' => SizedBox.square(dimension: size, child: const RepaintBoundary(child: CustomPaint(painter: _BubblesIcon()))),
        'creature' => SizedBox.square(dimension: size, child: RepaintBoundary(child: CustomPaint(painter: CreaturePainter(_creature)))),
        'compare' => CompareIcon(size: size),
        'dots' => SizedBox.square(dimension: size, child: RepaintBoundary(child: CustomPaint(painter: _DotsIcon(DTheme.of(context).text.kidTitle)))),
        _ => DEmoji(game.emoji, size: size),
      };
}

class _BubblesIcon extends CustomPainter {
  const _BubblesIcon();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    const bubbles = [(0.42, 0.58, 0.3, Color(0xFFA066E8)), (0.76, 0.3, 0.19, Color(0xFFF06BA8)), (0.8, 0.76, 0.12, Color(0xFFF7C531)), (0.2, 0.2, 0.1, Color(0xFF4CC46A))];
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.022
      ..color = Colors.white.withValues(alpha: 0.95);
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final (x, y, r, color) in bubbles) {
      final c = Offset(x * s, y * s), radius = r * s;
      final fill = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          colors: [Colors.white.withValues(alpha: 0.9), color.withValues(alpha: 0.7), color],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: radius));
      canvas
        ..drawCircle(c, radius, fill)
        ..drawCircle(c, radius, rim)
        ..drawOval(Rect.fromCenter(center: c + Offset(-radius * 0.38, -radius * 0.42), width: radius * 0.42, height: radius * 0.26), shine);
    }
  }

  @override
  bool shouldRepaint(_BubblesIcon old) => false;
}

/// Dot-to-Dot's tile: the star's five numbered dots, joined from 1 to 3
/// along its outline.
class _DotsIcon extends CustomPainter {
  const _DotsIcon(this.font);
  final TextStyle font;

  @override
  void paint(Canvas canvas, Size size) {
    final g = DotGeometry.of(dotArtOf('star'), 5);
    canvas.save();
    canvas.scale(size.shortestSide / 1000);
    Paint line(double alpha, double width) => Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(g.between(g.dots[2], g.length), line(0.35, 18));
    canvas.drawPath(g.between(0, g.dots[2]), line(1, 58));
    for (var i = 0; i < g.points.length; i++) {
      canvas.drawCircle(g.points[i], 92, Paint()..color = Colors.white);
      final label = TextPainter(
        text: TextSpan(text: '${i + 1}', style: font.copyWith(fontSize: 110, height: 1, fontWeight: FontWeight.w700, color: const Color(0xFF2B2440))),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, g.points[i] - Offset(label.width / 2, label.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DotsIcon old) => old.font != font;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.dense = false});
  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? t.space.sm : t.space.md, vertical: dense ? t.space.xxs : t.space.xs),
      decoration: BoxDecoration(color: t.colors.surfaceRaised, borderRadius: t.radius.pill, boxShadow: t.elevation.e1),
      child: Text(text, style: (dense ? t.text.label : t.text.title).copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

/// Settings live behind a 3-second hold, then the PIN (SPEC §9.3).
class _GrownUpCorner extends ConsumerWidget {
  const _GrownUpCorner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    return DHoldToActivate(
      id: 'toybox.grownups',
      semanticLabel: 'Grown-ups: hold for the Toybox settings',
      onActivated: () => unawaited(() async {
        if (await ensureGrownUp(context, ref, reason: 'The Toybox settings are for grown-ups')) ref.read(routerProvider).go('/settings/toybox');
      }()),
      child: Container(
        width: 48 * t.scale,
        height: 48 * t.scale,
        decoration: BoxDecoration(color: t.colors.surfaceSunken, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(Icons.settings_rounded, size: 24 * t.scale, color: t.colors.inkTertiary),
      ),
    );
  }
}

/// Out of time today, or outside the Toybox's hours.
class _Sleeping extends ConsumerWidget {
  const _Sleeping({required this.why});
  final String? why;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(toyboxSettingsProvider);
    final opens = why == 'hours' && s.opens != null ? 'It wakes up at ${s.opens}.' : 'Back tomorrow!';
    return Center(child: DEmptyState(id: 'toybox.sleeping', emoji: '😴', title: 'The Toybox is sleeping', message: opens));
  }
}
