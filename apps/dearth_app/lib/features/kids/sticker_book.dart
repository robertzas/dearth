import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/household_data.dart';
import '../../core/providers.dart';
import 'celebration.dart';
import 'kids_data.dart';
import 'kids_ops.dart';

/// Stickers per page before the book turns to a fresh one.
const int kStickersPerPage = 20;

/// The sticker book (SPEC FR-KID-12): every earned sticker is chosen and
/// placed anywhere on a themed scene; finished pages stay in the book.
Future<void> openStickerBook(BuildContext context, Profile kid) {
  final t = DTheme.of(context);
  return Navigator.of(context, rootNavigator: true).push<void>(PageRouteBuilder<void>(
    transitionDuration: t.motion(DMotion.standard),
    reverseTransitionDuration: t.motion(DMotion.fast),
    pageBuilder: (_, _, _) => StickerBookScreen(kid: kid),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

class StickerBookScreen extends ConsumerStatefulWidget {
  const StickerBookScreen({super.key, required this.kid});
  final Profile kid;

  @override
  ConsumerState<StickerBookScreen> createState() => _StickerBookScreenState();
}

class _StickerBookScreenState extends ConsumerState<StickerBookScreen> {
  final _random = math.Random();
  List<String> _choices = const [];
  String? _picked;
  int? _page;

  List<String> _deal(List<String> stickers) => ([...stickers]..shuffle(_random)).take(4).toList();

  Future<void> _place(Offset at, Size scene, int page) async {
    final sticker = _picked;
    if (sticker == null) return;
    setState(() => _picked = null);
    final w = ref.read(writerProvider);
    await w.commit(placeStickerOps(
      w.op,
      profileId: widget.kid.id,
      sticker: sticker,
      x: at.dx / scene.width,
      y: at.dy / scene.height,
      page: page,
      rotation: (_random.nextDouble() - 0.5) * 0.6,
      nowMs: ref.read(appClockProvider).nowMs(),
    ));
    if (!mounted) return;
    celebrate(context, emoji: sticker, message: 'Beautiful!');
    setState(() => _choices = const []);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final kid = widget.kid;
    final placed = ref.watch(stickerPlacementsProvider(kid.id)).value ?? const <StickerPlacement>[];
    final toPlace = stickersToPlace(ref.watch(balancesProvider(kid.id)), placed.length);
    final themeId = ref.watch(stickerThemeProvider(kid.id));
    final theme = kStickerThemes[themeId]!;
    if (_choices.isEmpty) _choices = _deal(theme.$3);
    final newPage = placed.length ~/ kStickersPerPage;
    final lastPage = math.max(newPage, placed.isEmpty ? 0 : placed.last.page);
    final page = (_page ?? newPage).clamp(0, lastPage);
    final onPage = [for (final p in placed) if (p.page == page) p];
    final placing = _picked != null && page == newPage;
    return screenTid(
      'screen.stickers',
      Material(
        color: t.colors.surface,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(t.pageMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DIconButton(icon: Icons.close_rounded, label: 'Close', id: 'stickers.close', tone: DButtonTone.ghost, onPressed: () => Navigator.of(context).pop()),
                    SizedBox(width: t.space.sm),
                    Expanded(child: Text('${kid.name}’s sticker book · ${theme.$1}', style: t.text.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DIconButton(icon: Icons.chevron_left_rounded, label: 'Previous page', id: 'stickers.prev', onPressed: page > 0 ? () => setState(() => _page = page - 1) : null),
                    Text('Page ${page + 1}', style: t.text.label),
                    DIconButton(icon: Icons.chevron_right_rounded, label: 'Next page', id: 'stickers.next', onPressed: page < lastPage ? () => setState(() => _page = page + 1) : null),
                  ],
                ),
                SizedBox(height: t.space.sm),
                Expanded(
                  child: ClipRRect(
                    borderRadius: t.radius.card,
                    child: LayoutBuilder(builder: (context, box) {
                      final size = box.biggest;
                      final s = math.min(size.width, size.height) * 0.11;
                      return tid(
                        'stickers.scene',
                        // Placement needs the pointer position, which semantics
                        // can't carry; the detector stays out of the tree so the
                        // scene keeps its id.
                        GestureDetector(
                          excludeFromSemantics: true,
                          behavior: HitTestBehavior.opaque,
                          // Always listening, and asking at the tap: a tap right
                          // after picking can land before the frame that would
                          // attach a handler, and quick little fingers do that.
                          onTapUp: (d) {
                            if (_picked != null && page == newPage) _place(d.localPosition, size, page);
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              RepaintBoundary(child: CustomPaint(painter: ScenePainter(theme.$2))),
                              for (final p in onPage)
                                Positioned(
                                  left: p.x * size.width - s / 2,
                                  top: p.y * size.height - s / 2,
                                  child: Transform.rotate(angle: p.rotation, child: DEmoji(p.sticker, size: s * p.scale)),
                                ),
                              if (placing)
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    margin: EdgeInsets.only(top: t.space.md),
                                    padding: EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
                                    decoration: BoxDecoration(color: t.colors.surfaceRaised.withValues(alpha: 0.9), borderRadius: t.radius.pill),
                                    child: Text('Now tap where it goes!', style: t.text.kidBody),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(height: t.space.md),
                if (toPlace > 0 && page == newPage)
                  Column(
                    children: [
                      tid('stickers.prompt', Text(_picked == null ? 'Pick a sticker!' : 'Great choice!', style: t.text.kidTitle)),
                      SizedBox(height: t.space.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final (i, sticker) in _choices.indexed)
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                              child: DPressable(
                                id: 'stickers.choice.$i',
                                semanticLabel: 'Sticker $sticker',
                                selected: _picked == sticker,
                                excludeSemantics: true,
                                borderRadius: t.radius.pill,
                                onTap: () => setState(() => _picked = sticker),
                                child: AnimatedContainer(
                                  duration: t.motion(DMotion.fast),
                                  padding: EdgeInsets.all(t.space.sm),
                                  decoration: BoxDecoration(
                                    color: _picked == sticker ? t.colors.accentTint : t.colors.surfaceRaised,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _picked == sticker ? t.colors.accent : t.colors.outline, width: 3),
                                  ),
                                  child: DEmoji(sticker, size: 64 * t.scale),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  )
                else
                  Center(child: Text(page == newPage ? 'Do a job to earn a new sticker! ⭐' : 'A finished page 🌟', style: t.text.kidBody)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple painted scene per sticker theme's background.
class ScenePainter extends CustomPainter {
  ScenePainter(this.background);
  final String background;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void sky(Color top, Color bottom) => canvas.drawRect(
          Offset.zero & size,
          Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(Offset.zero & size),
        );
    void hill(double y, double amp, Color c) {
      final path = Path()..moveTo(0, h * y);
      for (var x = 0.0; x <= w; x += w / 24) {
        path.lineTo(x, h * y + math.sin(x / w * math.pi * 2.2) * h * amp);
      }
      path
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(path, Paint()..color = c);
    }

    switch (background) {
      case 'ocean':
        sky(const Color(0xFF8FD3F4), const Color(0xFF1E6FB8));
        hill(0.88, 0.02, const Color(0xFFF2D49B));
      case 'space':
        sky(const Color(0xFF0B1033), const Color(0xFF2B1B5A));
        final r = math.Random(3);
        for (var i = 0; i < 80; i++) {
          canvas.drawCircle(Offset(r.nextDouble() * w, r.nextDouble() * h), 1 + r.nextDouble() * 2, Paint()..color = Colors.white.withValues(alpha: 0.4 + r.nextDouble() * 0.6));
        }
        canvas.drawCircle(Offset(w * 0.85, h * 0.2), h * 0.09, Paint()..color = const Color(0xFFF2A65A));
      case 'jungle':
        sky(const Color(0xFFBFE8C0), const Color(0xFF7CC47F));
        hill(0.7, 0.04, const Color(0xFF4F9D58));
        hill(0.85, 0.03, const Color(0xFF3B7D45));
      case 'garden':
        sky(const Color(0xFFDDF1FF), const Color(0xFFFFF4D6));
        hill(0.78, 0.02, const Color(0xFF9BD27F));
      case 'city':
        sky(const Color(0xFFB9E2FF), const Color(0xFFEAF6FF));
        final r = math.Random(5);
        var x = 0.0;
        while (x < w) {
          final bw = w * (0.06 + r.nextDouble() * 0.06), bh = h * (0.2 + r.nextDouble() * 0.3);
          canvas.drawRect(Rect.fromLTWH(x, h * 0.85 - bh, bw - 4, bh), Paint()..color = Color.lerp(const Color(0xFF9AA5B8), const Color(0xFF6B7690), r.nextDouble())!);
          x += bw;
        }
        canvas.drawRect(Rect.fromLTWH(0, h * 0.85, w, h * 0.15), Paint()..color = const Color(0xFF8C939E));
      default: // farm
        sky(const Color(0xFFBDE6FF), const Color(0xFFE8F7FF));
        canvas.drawCircle(Offset(w * 0.86, h * 0.16), h * 0.08, Paint()..color = const Color(0xFFFFD45C));
        hill(0.62, 0.05, const Color(0xFF9AD27C));
        hill(0.78, 0.04, const Color(0xFF7BBF5E));
    }
  }

  @override
  bool shouldRepaint(ScenePainter old) => old.background != background;
}
