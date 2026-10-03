import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import 'event_editor.dart';
import 'event_ops.dart';
import 'event_visuals.dart';

/// Opens quick add in a sheet (phone Add button, Home).
Future<void> showQuickAdd(BuildContext context) => showDSheet<void>(
      context,
      title: 'Add to the calendar',
      id: 'quickadd.sheet',
      builder: (sheet) => QuickAddField(autofocus: true, onAdded: () => Navigator.of(sheet).pop()),
    );

/// Natural-language event entry with a live preview (FR-CAL-12).
class QuickAddField extends ConsumerStatefulWidget {
  const QuickAddField({super.key, this.autofocus = false, this.onAdded, this.compact = false});
  final bool autofocus;
  final VoidCallback? onAdded;
  final bool compact;

  @override
  ConsumerState<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends ConsumerState<QuickAddField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  QuickAddResult? _result;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _parse(String s) {
    setState(() => _result = parseQuickAdd(s, today: ref.read(todayProvider), peopleByWord: ref.read(peopleWordsProvider)));
  }

  EventDraft? _draft() {
    final r = _result;
    if (r == null) return null;
    final learned = ref.read(learnedIconsProvider);
    return EventDraft(
      title: r.title,
      icon: suggestEventIcon(r.title, learned: learned),
      date: r.date,
      endDate: r.endDate,
      allDay: r.allDay,
      startMinute: r.startMinute ?? 9 * 60,
      durationMinutes: r.durationMinutes,
      profileIds: r.profileIds,
      sourceId: ref.read(defaultCalendarProvider)?.id ?? Ids.familyCalendar,
    );
  }

  Future<void> _add() async {
    final d = _draft();
    if (d == null) return;
    final writer = ref.read(writerProvider);
    await writer.commit(createEventOps(writer.op, d, ref.read(householdTimeProvider)));
    _text.clear();
    setState(() => _result = null);
    ref.read(toastProvider).show('Added “${d.title}”', emoji: d.icon ?? '📅');
    widget.onAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DTextField(
          id: 'quickadd.input',
          controller: _text,
          focusNode: _focus,
          autofocus: widget.autofocus,
          hint: 'Quick add: “Swim Saturday 9am Ava”',
          prefix: Icon(Icons.auto_awesome_rounded, color: t.colors.accent),
          textInputAction: TextInputAction.done,
          onChanged: _parse,
          onSubmitted: (_) => _add(),
        ),
        AnimatedSize(
          duration: t.motion(DMotion.fast),
          curve: DMotion.standardCurve,
          alignment: Alignment.topCenter,
          child: r == null ? const SizedBox(width: double.infinity) : _Preview(result: r, onAdd: _add, onMore: _more),
        ),
      ],
    );
  }

  Future<void> _more() async {
    final d = _draft();
    if (d == null) return;
    widget.onAdded?.call();
    _text.clear();
    setState(() => _result = null);
    await showEventEditor(context, ref, draft: d);
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.result, required this.onAdd, required this.onMore});
  final QuickAddResult result;
  final VoidCallback onAdd;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final people = ref.watch(profileMapProvider);
    final today = ref.watch(todayProvider);
    final h24 = ref.watch(clock24Provider);
    final learned = ref.watch(learnedIconsProvider);
    final palette = draftPalette(t, result.profileIds, people);
    final who = [for (final id in result.profileIds) ?people[id]];
    final when = result.allDay
        ? '${relativeDayName(result.date, today)}, ${monthDay(result.date)}${result.endDate != null ? ' – ${monthDay(result.endDate!.addDays(-1))}' : ''} · All day'
        : '${relativeDayName(result.date, today)}, ${monthDay(result.date)} · '
            '${formatTime(DateTime(2000, 1, 1, result.startMinute! ~/ 60, result.startMinute! % 60), h24: h24)} · ${formatDuration(result.durationMinutes)}';
    return Padding(
      padding: EdgeInsets.only(top: t.space.sm),
      child: tid(
        'quickadd.preview',
        Container(
          padding: EdgeInsets.all(t.space.sm),
          decoration: BoxDecoration(color: palette.tint, borderRadius: t.radius.card),
          child: Row(
            children: [
              DEmoji(suggestEventIcon(result.title, learned: learned) ?? '📅', size: 40 * t.scale),
              SizedBox(width: t.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.title, style: t.text.bodyStrong.copyWith(color: palette.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(when, style: t.text.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (who.isNotEmpty) ...[AvatarStack(people: who, size: 32 * t.scale), SizedBox(width: t.space.sm)],
              DIconButton(icon: Icons.tune_rounded, label: 'More options', id: 'quickadd.more', tone: DButtonTone.ghost, onPressed: onMore),
              SizedBox(width: t.space.xs),
              DButton(label: 'Add', icon: Icons.add_rounded, size: DButtonSize.sm, id: 'quickadd.add', onPressed: onAdd),
            ],
          ),
        ),
      ),
    );
  }
}
