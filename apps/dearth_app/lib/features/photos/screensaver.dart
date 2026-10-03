import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/display_state.dart';
import '../../app/grown_up.dart';
import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';
import '../calendar/event_visuals.dart';
import 'art_pack.dart';
import 'photos_data.dart';

/// The photo frame (SPEC §10.4 FR-SSV): crossfades (ambient 1.2 s), pairs
/// portraits on landscape screens, uses Hub pre-blurred backgrounds (no
/// runtime blur), precaches the next slide, and falls back to the art pack.
/// A tap only wakes; a long press opens photo options (grown-up).
class Screensaver extends ConsumerStatefulWidget {
  const Screensaver({super.key});

  @override
  ConsumerState<Screensaver> createState() => _ScreensaverState();
}

class _ScreensaverState extends ConsumerState<Screensaver> with SingleTickerProviderStateMixin {
  final _deck = SlideDeck();
  late final AnimationController _fade = AnimationController(vsync: this, duration: DMotion.ambient, value: 1);
  Slide? _current;
  Slide? _previous;
  Slide? _upcoming;
  Timer? _timer;
  Timer? _precache;

  bool get _landscape {
    final s = MediaQuery.sizeOf(context);
    return s.width >= s.height;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_current == null) {
      _current = _draw();
      _upcoming = _draw();
      _schedule();
    }
  }

  Slide _draw() => _deck.next(ref.read(screensaverPoolProvider), landscape: _landscape, artCount: kArtCount);

  int get _seconds => (ref.read(settingMapProvider(SettingKeys.screensaver))['photoSeconds'] as num?)?.toInt().clamp(10, 120) ?? 30;

  void _schedule() {
    _timer?.cancel();
    _precache?.cancel();
    final period = Duration(seconds: _seconds);
    _precache = Timer(period - const Duration(seconds: 5), () {
      if (mounted && _upcoming != null) _precacheSlide(_upcoming!);
    });
    _timer = Timer(period, _advance);
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      _previous = _current;
      _current = _upcoming ?? _draw();
      _upcoming = _draw();
    });
    _fade.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _previous = null);
    });
    _schedule();
  }

  void _precacheSlide(Slide s) {
    final api = ref.read(hubApiProvider);
    if (api == null || s.photos.isEmpty) return;
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final p in s.photos) {
      final url = _photoUrl(api, p, size, dpr, s.photos.length);
      if (url != null) precacheImage(NetworkImage(url), context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _precache?.cancel();
    _fade.dispose();
    super.dispose();
  }

  Future<void> _options() async {
    final slide = _current;
    if (slide == null || slide.photos.isEmpty) return;
    if (!await ensureGrownUp(context, ref, reason: 'Photo options')) return;
    if (!mounted) return;
    final p = slide.photos.first;
    final w = ref.read(writerProvider);
    await showDSheet<void>(
      context,
      title: 'This photo',
      id: 'ss.options',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.takenMs != null || p.caption != null)
              Padding(padding: EdgeInsets.only(bottom: t.space.md), child: Text(_caption(ref, p) ?? '', style: t.text.body)),
            DListRow(
              id: 'ss.favorite',
              title: p.favorite ? 'Remove from favorites' : 'Favorite',
              leading: const DEmoji('⭐', size: 30),
              onTap: () {
                w.upsert('photo_items', p.id, {'favorite': !p.favorite});
                Navigator.of(sheet).pop();
              },
            ),
            DListRow(
              id: 'ss.hide',
              title: 'Hide everywhere',
              subtitle: 'It won’t show on any display',
              leading: const DEmoji('🙈', size: 30),
              onTap: () {
                w.upsert('photo_items', p.id, {'hidden': true});
                Navigator.of(sheet).pop();
                _advance();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ss = ref.watch(settingMapProvider(SettingKeys.screensaver));
    final kenBurns = (ss['kenBurns'] as bool? ?? false) && ref.watch(perfTierProvider) != PerfTier.t1;
    return tid(
      'screensaver',
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(displayProvider.notifier).wake(),
        onLongPress: _options,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_previous != null) _SlideView(slide: _previous!, kenBurns: false, key: ValueKey('p-${_previous!.key}')),
              if (_current != null)
                FadeTransition(
                  opacity: CurvedAnimation(parent: _fade, curve: Curves.easeInOut),
                  child: _SlideView(slide: _current!, kenBurns: kenBurns, seconds: _seconds, key: ValueKey('c-${_current!.key}')),
                ),
              _Overlays(slide: _current, settings: ss),
            ],
          ),
        ),
      ),
    );
  }
}

String? _photoUrl(HubApi api, PhotoItem p, Size screen, double dpr, int count) {
  final sha = blobSha(p.blobRef);
  if (sha == null) return null;
  final w = (screen.width / count * dpr).round();
  final h = (screen.height * dpr).round();
  return api.blobUrl(sha, width: w, height: h, cover: count > 1).toString();
}

String? _caption(WidgetRef ref, PhotoItem p) {
  final parts = <String>[];
  if (p.takenMs != null) {
    final time = ref.read(householdTimeProvider);
    final taken = time.dateOfMs(p.takenMs!);
    final today = time.today();
    final years = today.year - taken.year;
    if (taken.month == today.month && taken.day == today.day && years > 0) {
      parts.add('$years ${years == 1 ? 'year' : 'years'} ago today');
    } else {
      parts.add(DateFormat('MMMM y').format(taken.utcMidnight));
    }
  }
  if (p.location != null) parts.add(p.location!);
  if (p.caption != null && p.caption!.isNotEmpty) parts.add(p.caption!);
  return parts.isEmpty ? null : parts.join(' · ');
}

class _SlideView extends ConsumerStatefulWidget {
  const _SlideView({super.key, required this.slide, required this.kenBurns, this.seconds = 30});
  final Slide slide;
  final bool kenBurns;
  final int seconds;

  @override
  ConsumerState<_SlideView> createState() => _SlideViewState();
}

class _SlideViewState extends ConsumerState<_SlideView> with SingleTickerProviderStateMixin {
  late final AnimationController _kb = AnimationController(vsync: this, duration: Duration(seconds: widget.seconds + 2));

  @override
  void initState() {
    super.initState();
    if (widget.kenBurns) _kb.forward();
  }

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slide;
    if (s.art != null) return ArtScene(s.art!);
    final api = ref.watch(hubApiProvider);
    if (api == null) return ArtScene(s.photos.first.id.hashCode.abs() % kArtCount);
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final landscape = size.width >= size.height;
    Widget image(PhotoItem p, {required BoxFit fit, required int count}) {
      final url = _photoUrl(api, p, size, dpr, count);
      if (url == null) return const SizedBox.shrink();
      return Image.network(
        url,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => ArtScene(p.id.hashCode.abs() % kArtCount),
      );
    }

    Widget content;
    if (s.photos.length == 2) {
      content = Row(
        children: [
          Expanded(child: image(s.photos[0], fit: BoxFit.cover, count: 2)),
          const SizedBox(width: 6),
          Expanded(child: image(s.photos[1], fit: BoxFit.cover, count: 2)),
        ],
      );
    } else {
      final p = s.photos.first;
      final matches = isPortrait(p) != landscape;
      if (matches || p.width == null) {
        content = image(p, fit: BoxFit.cover, count: 1);
      } else {
        // Mismatched orientation: Hub pre-blurred background + whole photo.
        final sha = blobSha(p.blobRef)!;
        content = Stack(
          fit: StackFit.expand,
          children: [
            Image.network(api.blobUrl(sha, width: 640, blur: true).toString(), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black)),
            image(p, fit: BoxFit.contain, count: 1),
          ],
        );
      }
    }
    if (!widget.kenBurns) return content;
    final dir = s.key.hashCode.isEven ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _kb,
      builder: (context, child) => Transform.scale(
        scale: 1.0 + 0.06 * _kb.value,
        alignment: Alignment(0.3 * dir, -0.2 * dir),
        child: child,
      ),
      child: content,
    );
  }
}

class _Overlays extends ConsumerWidget {
  const _Overlays({required this.slide, required this.settings});
  final Slide? slide;
  final Map<String, Object?> settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    bool on(String k) => settings[k] as bool? ?? true;
    final time = ref.watch(householdTimeProvider);
    final now = ref.watch(nowMinuteMsProvider);
    final h24 = ref.watch(clock24Provider);
    final imperial = ref.watch(imperialProvider);
    final wx = ref.watch(weatherProvider).value?.current;
    final next = ref.watch(upNextProvider);
    final ctx = EventContext.watch(ref);
    final wall = time.wall(now);
    final minute = now ~/ 60000;
    // Drift a few pixels every minute against uneven panel aging (FR-SSV-05).
    final drift = Offset(math.sin(minute / 7) * 10, math.cos(minute / 11) * 6) * t.scale;
    const white = Colors.white;
    final shadow = [Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12)];
    final caption = slide == null ? null : (slide!.art != null ? kArtTitles[slide!.art!] : _caption(ref, slide!.photos.first));

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x8C000000)]),
              ),
            ),
          ),
          Positioned(
            left: t.space.xxl + drift.dx,
            right: t.space.xxl - drift.dx,
            bottom: t.space.xl + drift.dy,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (on('clock'))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      tid('ss.clock', Text(formatClock(wall, h24: h24), style: t.text.clockXL.copyWith(color: white, shadows: shadow))),
                      Text(
                        [
                          DateFormat('EEEE, MMM d').format(wall),
                          if (on('weather') && wx != null) '${conditionEmoji(wx.condition, isDay: wx.isDay)} ${formatTemp(wx.tempC, imperial: imperial)}',
                        ].join('  ·  '),
                        style: t.text.title.copyWith(color: white, shadows: shadow),
                      ),
                    ],
                  ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (on('nextEvent') && next != null)
                      Text(
                        '${eventEmoji(next.occurrence.event, learned: ctx.learned)} ${next.occurrence.event.title} ${next.occurrence.startMs <= now ? 'now' : formatIn(now, next.occurrence.startMs)}',
                        style: t.text.title.copyWith(color: white, shadows: shadow),
                      ),
                    if (on('caption') && caption != null) ...[
                      SizedBox(height: t.space.xxs),
                      Text(caption, style: t.text.body.copyWith(color: white.withValues(alpha: 0.85), shadows: shadow)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Night mode: a dim, warm clock that slowly moves (SPEC FR-DSP-04).
class NightClock extends ConsumerWidget {
  const NightClock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    const c = DColors.night;
    final time = ref.watch(householdTimeProvider);
    final now = ref.watch(nowMinuteMsProvider);
    final h24 = ref.watch(clock24Provider);
    final wall = time.wall(now);
    final slot = now ~/ 600000; // moves every 10 minutes
    final align = Alignment(math.sin(slot * 1.3) * 0.5, math.cos(slot * 0.9) * 0.35);
    final tomorrow = ref.watch(occurrencesProvider(DayRange.single(time.today().addDays(1)))).value?.where((o) => !o.allDay).firstOrNull;
    return tid(
      'nightclock',
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(displayProvider.notifier).wake(),
        child: ColoredBox(
          color: c.surface,
          child: Align(
            alignment: align,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DEmoji('🌙', size: 56),
                Text(formatClock(wall, h24: h24), style: t.text.clockXL.copyWith(color: c.inkPrimary)),
                Text(DateFormat('EEEE, MMMM d').format(wall), style: t.text.title.copyWith(color: c.inkSecondary)),
                if (tomorrow != null) ...[
                  SizedBox(height: t.space.md),
                  Text(
                    'Tomorrow ${formatTime(time.wall(tomorrow.startMs), h24: h24)} · ${tomorrow.event.title}',
                    style: t.text.body.copyWith(color: c.inkTertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
