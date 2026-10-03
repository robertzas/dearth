import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../shared/pickers.dart';
import 'event_ops.dart';
import 'event_sheet.dart';
import 'event_visuals.dart';

/// Opens the editor for a new event ([draft]) or an existing [occurrence].
Future<void> showEventEditor(BuildContext context, WidgetRef ref, {Occurrence? occurrence, EventDraft? draft}) async {
  final time = ref.read(householdTimeProvider);
  Event? master;
  if (occurrence != null && occurrence.event.recurringParentId != null) {
    (master, _) = await loadSeries(ref, occurrence);
  }
  final initial = draft ??
      (occurrence != null
          ? EventDraft.fromOccurrence(occurrence, time, master: master)
          : EventDraft(
              title: '',
              date: ref.read(todayProvider),
              sourceId: ref.read(defaultCalendarProvider)?.id ?? Ids.familyCalendar,
              startMinute: _nextHalfHour(time),
            ));
  if (!context.mounted) return;
  await showDSheet<void>(
    context,
    title: occurrence == null ? 'New event' : 'Edit event',
    id: 'event.editor',
    builder: (_) => _EventEditor(initial: initial, occurrence: occurrence),
  );
}

int _nextHalfHour(HouseholdTime time) {
  final m = time.minuteOfDay(time.nowMs());
  return ((m ~/ 30) + 1) * 30 % (24 * 60);
}

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({required this.initial, this.occurrence});
  final EventDraft initial;
  final Occurrence? occurrence;

  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  late EventDraft _d = widget.initial;
  late final _title = TextEditingController(text: widget.initial.title);
  late final _location = TextEditingController(text: widget.initial.location ?? '');
  late final _notes = TextEditingController(text: widget.initial.notes ?? '');
  late bool _iconPicked = widget.initial.icon != null;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  RepeatPreset get _preset {
    final r = _d.rrule;
    if (r == null || r.isEmpty) return RepeatPreset.none;
    for (final p in const [RepeatPreset.daily, RepeatPreset.weekdays, RepeatPreset.weekly, RepeatPreset.biweekly, RepeatPreset.monthlyByDay, RepeatPreset.yearly]) {
      if (buildRrule(p, _d.date) == r) return p;
    }
    return RepeatPreset.custom;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    final learned = ref.read(learnedIconsProvider);
    final d = _d.copyWith(
      title: title,
      icon: _iconPicked ? _d.icon : (suggestEventIcon(title, learned: learned) ?? _d.icon),
      location: _location.text,
      notes: _notes.text,
    );
    final o = widget.occurrence;
    final writer = ref.read(writerProvider);
    final time = ref.read(householdTimeProvider);
    var scope = EditScope.all;
    if (o != null && isRecurring(o)) {
      final picked = await pickScope(context, delete: false);
      if (picked == null) return;
      scope = picked;
    }
    setState(() => _saving = true);
    final List<Op> ops;
    if (o == null) {
      ops = createEventOps(writer.op, d, time);
    } else {
      final (master, exceptions) = isRecurring(o) ? await loadSeries(ref, o) : (null, const <Event>[]);
      ops = updateEventOps(writer.op, o, d, scope, time, master: master, exceptions: exceptions);
    }
    // Remember a hand-picked icon for future events with this title (FR-CAL-15).
    final suggestion = suggestEventIcon(title);
    if (_iconPicked && d.icon != null && d.icon != suggestion && learned[title.toLowerCase()] != d.icon) {
      ops.add(settingOp(writer, SettingKeys.learnedIcons, {...learned, title.toLowerCase(): d.icon}));
    }
    await writer.commit(ops);
    if (!mounted) return;
    Navigator.of(context).pop();
    ref.read(toastProvider).show(o == null ? 'Added “$title”' : 'Saved', emoji: d.icon ?? '📅');
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final h24 = ref.watch(clock24Provider);
    final family = ref.watch(familyProvider);
    final calendars = [for (final s in ref.watch(calendarSourcesProvider).value ?? const <CalendarSource>[]) if (s.writable) s];
    final learned = ref.watch(learnedIconsProvider);
    final emoji = _iconPicked ? (_d.icon ?? '📅') : (suggestEventIcon(_title.text, learned: learned) ?? _d.icon ?? '📅');
    final today = ref.watch(todayProvider);

    Widget label(String s) => Padding(padding: EdgeInsets.only(top: t.space.lg, bottom: t.space.xs), child: Text(s.toUpperCase(), style: t.text.overline));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DPressable(
              id: 'editor.icon',
              semanticLabel: 'Choose icon',
              onTap: () async {
                final picked = await pickEmoji(context);
                if (picked != null) {
                  setState(() {
                    _iconPicked = true;
                    _d = _d.copyWith(icon: picked);
                  });
                }
              },
              borderRadius: t.radius.card,
              child: Container(
                width: 72 * t.scale,
                height: 72 * t.scale,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: t.radius.card),
                child: DEmoji(emoji, size: 44 * t.scale),
              ),
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: DTextField(
                id: 'editor.title',
                controller: _title,
                hint: 'What’s happening?',
                big: true,
                autofocus: widget.occurrence == null,
                errorText: _error,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
          ],
        ),
        label('When'),
        DSwitchRow(
          id: 'editor.allday',
          title: 'All day',
          value: _d.allDay,
          onChanged: (v) => setState(() => _d = _d.copyWith(allDay: v, clearEndDate: true)),
        ),
        Wrap(
          spacing: t.space.sm,
          runSpacing: t.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DButton(
              id: 'editor.date',
              label: '${relativeDayName(_d.date, today)}, ${monthDay(_d.date)}',
              icon: Icons.event_rounded,
              tone: DButtonTone.neutral,
              onPressed: () async {
                final d = await pickDate(context, initial: _d.date);
                if (d != null) {
                  final span = _d.endDate == null ? null : _d.date.daysUntil(_d.endDate!);
                  setState(() => _d = _d.copyWith(date: d, endDate: span == null ? null : d.addDays(span), rrule: _rebuildRule(d)));
                }
              },
            ),
            if (_d.allDay)
              DButton(
                id: 'editor.enddate',
                label: _d.endDate == null || _d.date.daysUntil(_d.endDate!) <= 1 ? 'One day' : 'Until ${monthDay(_d.endDate!.addDays(-1))}',
                icon: Icons.date_range_rounded,
                tone: DButtonTone.neutral,
                onPressed: () async {
                  final last = await pickDate(context, initial: (_d.endDate ?? _d.date.addDays(1)).addDays(-1), title: 'Last day');
                  if (last != null && !last.isBefore(_d.date)) setState(() => _d = _d.copyWith(endDate: last.addDays(1)));
                },
              )
            else
              DButton(
                id: 'editor.time',
                label: formatTime(DateTime(2000, 1, 1, _d.startMinute ~/ 60, _d.startMinute % 60), h24: h24),
                icon: Icons.schedule_rounded,
                tone: DButtonTone.neutral,
                onPressed: () async {
                  final m = await pickTime(context, initial: _d.startMinute);
                  if (m != null) setState(() => _d = _d.copyWith(startMinute: m));
                },
              ),
          ],
        ),
        if (!_d.allDay) ...[
          SizedBox(height: t.space.sm),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final m in const [15, 30, 45, 60, 90, 120, 180, 240])
                DChip(id: 'editor.duration.$m', label: formatDuration(m), selected: _d.durationMinutes == m, dense: true, onTap: () => setState(() => _d = _d.copyWith(durationMinutes: m))),
            ],
          ),
        ],
        label('Repeat'),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final (p, name) in const [
              (RepeatPreset.none, 'Never'),
              (RepeatPreset.daily, 'Daily'),
              (RepeatPreset.weekdays, 'Weekdays'),
              (RepeatPreset.weekly, 'Weekly'),
              (RepeatPreset.biweekly, 'Every 2 weeks'),
              (RepeatPreset.monthlyByDay, 'Monthly'),
              (RepeatPreset.yearly, 'Yearly'),
            ])
              DChip(
                id: 'editor.repeat.${p.name}',
                label: name,
                dense: true,
                selected: _preset == p,
                onTap: () => setState(() => _d = p == RepeatPreset.none ? _d.copyWith(clearRrule: true) : _d.copyWith(rrule: buildRrule(p, _d.date))),
              ),
            if (_preset == RepeatPreset.custom) DChip(label: describeRrule(_d.rrule), selected: true, dense: true),
          ],
        ),
        if (family.isNotEmpty) ...[
          label('Who'),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final p in family)
                DChip(
                  id: 'editor.person.${p.id}',
                  label: p.name,
                  emoji: p.emoji,
                  personColor: t.person(p.color),
                  selected: _d.profileIds.contains(p.id),
                  onTap: () => setState(() {
                    final ids = [..._d.profileIds];
                    ids.contains(p.id) ? ids.remove(p.id) : ids.add(p.id);
                    _d = _d.copyWith(profileIds: ids);
                  }),
                ),
            ],
          ),
        ],
        if (calendars.length > 1) ...[
          label('Calendar'),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final s in calendars)
                DChip(
                  id: 'editor.calendar.${s.id}',
                  label: s.name,
                  dense: true,
                  selected: _d.sourceId == s.id,
                  leading: Container(width: 12 * t.scale, height: 12 * t.scale, decoration: BoxDecoration(color: Color(s.color), shape: BoxShape.circle)),
                  onTap: () => setState(() => _d = _d.copyWith(sourceId: s.id)),
                ),
            ],
          ),
        ],
        label('Details'),
        DTextField(id: 'editor.location', controller: _location, hint: 'Where?', prefix: Icon(Icons.place_outlined, color: c.inkTertiary)),
        SizedBox(height: t.space.sm),
        DTextField(id: 'editor.notes', controller: _notes, hint: 'Notes', maxLines: 4, prefix: Icon(Icons.notes_rounded, color: c.inkTertiary)),
        SizedBox(height: t.space.sm),
        DSwitchRow(
          id: 'editor.countdown',
          title: 'Count down on Home',
          subtitle: 'Shows days (and sleeps) until it',
          value: _d.countdown,
          onChanged: (v) => setState(() => _d = _d.copyWith(countdown: v)),
        ),
        SizedBox(height: t.space.lg),
        Row(
          children: [
            Expanded(child: DButton(label: 'Cancel', tone: DButtonTone.neutral, expand: true, id: 'editor.cancel', onPressed: () => Navigator.of(context).pop())),
            SizedBox(width: t.space.sm),
            Expanded(
              flex: 2,
              child: DButton(label: widget.occurrence == null ? 'Add event' : 'Save', icon: Icons.check_rounded, expand: true, busy: _saving, id: 'editor.save', onPressed: _save),
            ),
          ],
        ),
      ],
    );
  }

  /// Keeps weekly/monthly presets anchored on the new date.
  String? _rebuildRule(LocalDate d) {
    final p = _preset;
    if (p == RepeatPreset.none || p == RepeatPreset.custom) return _d.rrule;
    return buildRrule(p, d);
  }
}

/// Emoji choices for events (keyword icons first, then extras).
final List<String> kEventEmojiChoices = () {
  final seen = <String>{};
  return [
    for (final (_, e) in kEventIconRules)
      if (seen.add(e)) e,
    for (final e in const ['📅', '⭐', '🎉', '❤️', '🏠', '🚸', '🧑‍🍳', '🎒', '🧘', '🌳', '☀️', '🌧️'])
      if (seen.add(e)) e,
  ];
}();

Future<String?> pickEmoji(BuildContext context, {List<String>? choices, String title = 'Pick an icon'}) => showDSheet<String>(
      context,
      title: title,
      id: 'picker.emoji',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final (i, e) in (choices ?? kEventEmojiChoices).indexed)
              DPressable(
                id: 'picker.emoji.$i',
                onTap: () => Navigator.of(sheet).pop(e),
                semanticLabel: e,
                borderRadius: t.radius.card,
                child: Container(
                  width: 64 * t.scale,
                  height: 64 * t.scale,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.colors.surfaceSunken, borderRadius: t.radius.card),
                  child: DEmoji(e, size: 40 * t.scale),
                ),
              ),
          ],
        );
      },
    );

/// Builds the palette for an event draft preview (quick add chip).
EventPalette draftPalette(DTheme t, List<String> profileIds, Map<String, Profile> people) {
  final first = profileIds.map((id) => people[id]).whereType<Profile>().firstOrNull;
  final pc = first == null ? null : t.person(first.color);
  return EventPalette(
    solid: pc?.solid ?? t.colors.accent,
    tint: pc?.tint ?? t.colors.accentTint,
    ink: pc?.ink ?? t.colors.inkPrimary,
    stripes: [for (final id in profileIds) if (people[id] != null) t.person(people[id]!.color).solid],
  );
}
