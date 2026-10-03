import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';

/// Colors for an event: its people are the color (SPEC §11.1 #2); events
/// without people use their calendar's color.
@immutable
class EventPalette {
  const EventPalette({required this.solid, required this.tint, required this.ink, required this.stripes});
  final Color solid;
  final Color tint;
  final Color ink;

  /// One solid per person (≥ 2 → striped edge, FR-CAL-11).
  final List<Color> stripes;
}

EventPalette eventPalette(DTheme t, Occurrence o, Map<String, Profile> people, Map<String, CalendarSource> sources) {
  final who = [for (final id in o.profileIds) ?people[id]];
  if (who.isNotEmpty) {
    final first = t.person(who.first.color);
    return EventPalette(solid: first.solid, tint: first.tint, ink: first.ink, stripes: [for (final p in who) t.person(p.color).solid]);
  }
  final raw = o.event.color ?? sources[o.event.sourceId]?.color ?? 0xFF5B5BD6;
  final solid = Color(raw);
  final hsl = HSLColor.fromColor(solid);
  final ink = t.colors.isDark
      ? hsl.withLightness((hsl.lightness + 0.18).clamp(0, 0.85)).toColor()
      : hsl.withLightness((hsl.lightness - 0.22).clamp(0.15, 1)).toColor();
  final adjusted = t.colors.mode == DThemeMode.night ? hsl.withLightness(0.22).toColor() : solid;
  return EventPalette(solid: adjusted, tint: t.colors.tintOf(adjusted), ink: t.colors.mode == DThemeMode.night ? t.colors.inkPrimary : ink, stripes: [adjusted]);
}

/// The event's emoji: explicit icon, learned override, keyword match, or 📅.
String eventEmoji(Event e, {Map<String, String> learned = const {}}) {
  if (e.icon != null && e.icon!.isNotEmpty) return e.icon!;
  return suggestEventIcon(e.title, learned: learned) ?? '📅';
}

/// Reads the lookup maps an event row needs (narrow selects keep rebuilds cheap).
class EventContext {
  const EventContext(this.people, this.sources, this.learned);
  final Map<String, Profile> people;
  final Map<String, CalendarSource> sources;
  final Map<String, String> learned;

  static EventContext watch(WidgetRef ref) =>
      EventContext(ref.watch(profileMapProvider), ref.watch(calendarSourceMapProvider), ref.watch(learnedIconsProvider));
}

/// Overlapping person avatars (multi-person events).
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.people, required this.size, this.max = 4});
  final List<Profile> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final t = DTheme.of(context);
    final shown = people.take(max).toList();
    final step = size * 0.62;
    return Semantics(
      label: people.map((p) => p.name).join(', '),
      child: SizedBox(
        width: size + step * (shown.length - 1) + (people.length > max ? step : 0),
        height: size,
        child: Stack(
          children: [
            for (final (i, p) in shown.indexed)
              Positioned(
                left: i * step,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.colors.surfaceRaised, width: 2)),
                  child: DAvatar(colorIndex: p.color, emoji: p.emoji, name: p.name, size: size - 4, ring: false),
                ),
              ),
            if (people.length > max)
              Positioned(
                left: shown.length * step,
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.colors.surfaceSunken, shape: BoxShape.circle, border: Border.all(color: t.colors.surfaceRaised, width: 2)),
                  child: Text('+${people.length - max}', style: t.text.caption.copyWith(fontSize: size * 0.36, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tiny person-colored dots (dense views: month, week strip).
class PeopleDots extends StatelessWidget {
  const PeopleDots({super.key, required this.colors, required this.size, this.max = 5});
  final List<Color> colors;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in colors.take(max))
          Container(
            width: size,
            height: size,
            margin: EdgeInsets.only(right: size * 0.35),
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
      ],
    );
  }
}

/// A vertical edge in one or several person colors (stripes for groups).
class StripedEdge extends StatelessWidget {
  const StripedEdge({super.key, required this.colors, required this.width, this.radius});
  final List<Color> colors;
  final double width;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(radius ?? width);
    if (colors.length <= 1) {
      return Container(width: width, decoration: BoxDecoration(color: colors.firstOrNull ?? Colors.grey, borderRadius: BorderRadius.all(r)));
    }
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.all(r),
        child: Column(children: [for (final c in colors) Expanded(child: ColoredBox(color: c))]),
      ),
    );
  }
}
