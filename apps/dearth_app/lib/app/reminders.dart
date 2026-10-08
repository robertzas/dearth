import 'dart:async';
import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/data/calendar.dart';
import '../core/data/household.dart';
import '../core/format.dart';
import '../core/providers.dart';
import '../core/sound.dart';
import '../features/calendar/event_sheet.dart';
import '../features/calendar/event_visuals.dart';
import '../shared/face_photo.dart';
import 'display_state.dart';
import 'router.dart';

/// A reminder on screen since [shownMs].
@immutable
class ShownReminder {
  const ShownReminder(this.due, this.shownMs);
  final DueReminder due;
  final int shownMs;
}

/// On-display reminders (SPEC FR-CAL-20): every minute, and whenever events
/// change, works out which reminders are due; shows each once per device
/// (remembered across restarts), with a chime outside quiet hours. Runs for
/// the whole session (AppFrame watches it).
class ReminderController extends Notifier<List<ShownReminder>> {
  static const _kvKey = 'reminders.fired';

  /// A banner leaves after this long, or when its event ends.
  static const showFor = Duration(minutes: 10);
  static const maxShown = 3;

  /// Keys already fired on this device; null until loaded.
  Set<String>? _fired;

  @override
  List<ShownReminder> build() {
    ref.listen(nowMinuteMsProvider, (_, _) => _check());
    ref.listen(soonOccurrencesProvider, (_, _) => _check());
    ref.listen(calendarRemindersProvider, (_, _) => _check());
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    final raw = await ref.read(dbProvider).kvGet(_kvKey);
    _fired = decodeStringList(raw).toSet();
    _check();
  }

  void dismiss(ShownReminder r) => state = [for (final s in state) if (s != r) s];

  void _check() {
    final fired = _fired;
    final occ = ref.read(soonOccurrencesProvider).value;
    if (fired == null || occ == null) return;
    final now = ref.read(nowMinuteMsProvider);
    final sources = ref.read(calendarSourceMapProvider);
    final defaults = ref.read(calendarRemindersProvider);
    final due = dueReminders(
      occ,
      ref.read(householdTimeProvider),
      nowMs: now,
      fired: fired,
      leadsOf: (o) => effectiveReminders(o.event, writable: sources[o.event.sourceId]?.writable ?? true, calendarDefault: defaults[o.event.sourceId] ?? const []),
    );
    var shown = [for (final s in state) if (now - s.shownMs < showFor.inMilliseconds && now < s.due.occurrence.endMs) s];
    if (due.consumed.isNotEmpty) {
      fired.addAll(due.consumed);
      unawaited(_save(fired, now));
      // A display in Night or Off stays dark: the reminder counts as shown.
      final mode = ref.read(displayProvider).mode;
      if (due.show.isNotEmpty && mode != DisplayMode.night && mode != DisplayMode.off) {
        shown = [...shown, for (final d in due.show) ShownReminder(d, now)];
        if (shown.length > maxShown) shown = shown.sublist(shown.length - maxShown);
        if (!ref.read(isNightTimeProvider)) unawaited(ref.read(soundProvider).play(Sfx.reminder));
      }
    }
    if (!listEquals(shown, state)) state = shown;
  }

  /// Keeps keys of instances from the last two days (a key ends with
  /// `@startMs@lead`; event ids may contain `@` themselves).
  Future<void> _save(Set<String> fired, int now) async {
    final keep = [
      for (final k in fired)
        if ((int.tryParse(k.split('@').reversed.skip(1).firstOrNull ?? '') ?? 0) > now - const Duration(days: 2).inMilliseconds) k,
    ];
    fired.retainAll(keep);
    await ref.read(dbProvider).kvSet(_kvKey, jsonEncode(keep));
  }
}

final reminderProvider = NotifierProvider<ReminderController, List<ShownReminder>>(ReminderController.new);

/// "Ava", "Ava and Leo", "Ava, Leo and Max".
String joinNames(List<String> names) => switch (names.length) {
      0 => '',
      1 => names.single,
      _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
    };

/// A banner's headline and detail line. Reminders for kids talk to them by
/// name ("Ava, swim lesson in 15 minutes!", FR-CAL-20); grown-ups get the
/// title and the when.
(String, String) reminderText(DueReminder r, {required List<Profile> kids, required int nowMs, required HouseholdTime time, required bool h24}) {
  final o = r.occurrence;
  final e = o.event;
  final minutes = ((o.startMs - nowMs) / 60000).ceil();
  final today = time.dateOfMs(nowMs);
  final day = o.startDate ?? time.dateOfMs(o.startMs);
  final at = o.allDay ? null : formatTime(time.wall(o.startMs), h24: h24);
  final String when;
  if (o.allDay) {
    when = day == today ? 'Today' : (day == today.addDays(1) ? 'Tomorrow' : relativeDayName(day, today));
  } else if (minutes <= 0) {
    when = 'Now';
  } else if (minutes < 60) {
    when = 'In $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  } else {
    when = day == today ? 'At $at' : '${relativeDayName(day, today)} at $at';
  }
  final detail = [
    when,
    if (!o.allDay && minutes < 60 && minutes > 0) formatTimeRange(time.wall(o.startMs), time.wall(o.endMs), h24: h24),
    ?e.location,
  ].join(' · ');
  if (kids.isEmpty) return (e.title, detail);
  final names = joinNames([for (final k in kids) k.nickname?.trim().isNotEmpty ?? false ? k.nickname!.trim() : k.name]);
  final what = _softTitle(e.title, kids);
  // Mid-sentence: "today", "tomorrow", "on Saturday".
  final onDay = switch (today.daysUntil(day)) { 0 => 'today', 1 => 'tomorrow', _ => 'on ${weekdayLong(day)}' };
  final String headline;
  if (o.allDay) {
    headline = '$names, $what $onDay!';
  } else if (minutes <= 0) {
    headline = '$names, it’s time for $what!';
  } else if (minutes < 60) {
    headline = '$names, $what in $minutes ${minutes == 1 ? 'minute' : 'minutes'}!';
  } else {
    headline = '$names, $what ${day == today ? 'at $at' : '$onDay at $at'}!';
  }
  return (headline, detail);
}

/// Lower-cases a title's first letter for use mid-sentence, unless it
/// starts with a name ("Ava's birthday") or an acronym ("PTA night").
String _softTitle(String title, List<Profile> people) {
  final t = title.trim();
  if (t.length < 2) return t;
  final first = t.split(RegExp(r"[\s']")).first.toLowerCase();
  if (people.any((p) => p.name.toLowerCase() == first)) return t;
  if (t[1].toUpperCase() == t[1] && t[1].toLowerCase() != t[1]) return t;
  return t[0].toLowerCase() + t.substring(1);
}

/// The reminder banners at the top of the screen, above the app and the
/// photo frame (but not Night, which stays dark). Always mounted in
/// AppFrame, so the engine runs for the whole session.
class ReminderLayer extends ConsumerWidget {
  const ReminderLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(reminderProvider);
    if (shown.isEmpty) return const SizedBox.shrink();
    final t = DTheme.of(context);
    // Above the Navigator: needs its own Material (text style).
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.all(t.space.md),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 760 * t.scale),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final s in shown) _ReminderBanner(key: ValueKey(s.due.key), shown: s)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderBanner extends ConsumerWidget {
  const _ReminderBanner({super.key, required this.shown});
  final ShownReminder shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final o = shown.due.occurrence;
    final ctx = EventContext.watch(ref);
    final people = [for (final id in o.profileIds) ?ctx.people[id]];
    final kids = [for (final p in people) if (p.role == ProfileRole.child) p];
    final (headline, detail) = reminderText(
      shown.due,
      kids: kids,
      nowMs: ref.watch(nowMinuteMsProvider),
      time: ref.watch(householdTimeProvider),
      h24: ref.watch(clock24Provider),
    );
    final palette = eventPalette(t, o, ctx.people, ctx.sources);
    final emoji = eventEmoji(o.event, learned: ctx.learned);
    final size = 64 * t.scale;
    final banner = Container(
      margin: EdgeInsets.only(bottom: t.space.sm),
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: t.radius.card,
        border: Border.all(color: palette.solid, width: 3 * t.scale),
        boxShadow: t.elevation.e2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (kids.length == 1)
                  ProfileAvatar(kids.single, size: size)
                else
                  Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: palette.tint, borderRadius: t.radius.card),
                    child: DEmoji(emoji, size: size * 0.66),
                  ),
                if (kids.length == 1) Positioned(right: -6 * t.scale, bottom: -6 * t.scale, child: DEmoji(emoji, size: size * 0.5)),
              ],
            ),
          ),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                tid('reminder.title', Text(headline, style: (kids.isEmpty ? t.text.h2 : t.text.kidTitle).copyWith(fontSize: (kids.isEmpty ? 28 : 32) * t.scale), maxLines: 2, overflow: TextOverflow.ellipsis)),
                SizedBox(height: t.space.xxs),
                Text(detail, style: t.text.body.copyWith(color: c.inkSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          SizedBox(width: t.space.sm),
          DButton(
            label: 'OK',
            id: 'reminder.ok',
            onPressed: () => ref.read(reminderProvider.notifier).dismiss(shown),
          ),
        ],
      ),
    );
    return DPressable(
        id: 'reminder.banner',
        onTap: () {
          ref.read(reminderProvider.notifier).dismiss(shown);
          ref.read(displayProvider.notifier).wake();
          // Banners sit above the Navigator; the sheet opens on the app's.
          final nav = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
          if (nav != null) unawaited(showEventSheet(nav, ref, o));
        },
        semanticLabel: '$headline. $detail',
        pressedScale: 0.99,
        borderRadius: t.radius.card,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: t.motion(DMotion.standard),
          curve: DMotion.emphasizedCurve,
          builder: (context, v, child) => FractionalTranslation(translation: Offset(0, (v - 1) * 0.4), child: child),
          child: banner,
        ),
      );
  }
}
