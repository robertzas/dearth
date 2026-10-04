import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/grown_up.dart';
import '../../app/router.dart';
import '../../core/data/household.dart';
import 'game_host.dart';
import 'games/registry.dart';
import 'toybox_data.dart';

/// Each game's tile color: the launcher is read by picture and color.
const Map<String, Color> kGameHues = {
  'bubbles': Color(0xFF4FB3F6),
  'paint': Color(0xFFF06BA8),
  'coloring': Color(0xFFFF9F43),
  'farm': Color(0xFF5CC46B),
  'shapes': Color(0xFF9C6ADE),
  'music': Color(0xFF2EC4B6),
  'jigsaw': Color(0xFF4C7BF4),
  'memory': Color(0xFF7067E8),
  'monster': Color(0xFF8BC34A),
  'counting': Color(0xFFF5B82E),
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
                DAvatar(colorIndex: kid.color, emoji: kid.emoji, name: kid.name, size: 56 * t.scale),
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
      final cols = (box.maxWidth / (230 * t.scale)).floor().clamp(2, 5);
      final size = (box.maxWidth - gap * (cols - 1)) / cols;
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: t.pageMargin),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final g in games)
              _Tile(game: g, kid: kid, size: size, isNew: seen != null && !seen.contains(g.id)),
          ],
        ),
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
    final light = Color.lerp(hue, Colors.white, 0.35)!;
    final level = ref.watch(gameLevelProvider((kid.id, game.id)));
    final tile = DPressable(
      id: 'toybox.game.${game.id}',
      semanticLabel: game.title,
      excludeSemantics: true,
      borderRadius: BorderRadius.circular(t.radius.l),
      onTap: () => openGame(context, ref, game, kid),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius.l),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, hue]),
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
                    Text(game.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: t.text.title.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
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
/// bubble emoji is newer than Android 10, so the kitchen frame can't draw it).
class GameIcon extends StatelessWidget {
  const GameIcon(this.game, {super.key, required this.size});
  final GameInfo game;
  final double size;

  @override
  Widget build(BuildContext context) =>
      game.id == 'bubbles' ? SizedBox.square(dimension: size, child: const RepaintBoundary(child: CustomPaint(painter: _BubblesIcon()))) : DEmoji(game.emoji, size: size);
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
