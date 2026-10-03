import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/data/household.dart';
import '../core/format.dart';

/// Picks a household-local date from a month grid.
Future<LocalDate?> pickDate(BuildContext context, {required LocalDate initial, String title = 'Pick a date'}) =>
    showDSheet<LocalDate>(context, title: title, id: 'picker.date', builder: (_) => _DatePicker(initial: initial));

class _DatePicker extends ConsumerStatefulWidget {
  const _DatePicker({required this.initial});
  final LocalDate initial;

  @override
  ConsumerState<_DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends ConsumerState<_DatePicker> {
  late LocalDate _month = widget.initial.startOfMonth;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final weekStart = ref.watch(weekStartProvider);
    final today = ref.watch(todayProvider);
    final first = _month.startOfWeek(weekStart);
    final cell = 60 * t.scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            DIconButton(icon: Icons.chevron_left_rounded, label: 'Previous month', id: 'picker.date.prev', onPressed: () => setState(() => _month = _month.addMonths(-1))),
            Expanded(child: Text(monthYear(_month), textAlign: TextAlign.center, style: t.text.title)),
            DIconButton(icon: Icons.chevron_right_rounded, label: 'Next month', id: 'picker.date.next', onPressed: () => setState(() => _month = _month.addMonths(1))),
          ],
        ),
        SizedBox(height: t.space.sm),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: Text(weekdayShort(first.addDays(i)).substring(0, 2), textAlign: TextAlign.center, style: t.text.overline)),
          ],
        ),
        SizedBox(height: t.space.xs),
        for (var w = 0; w < 6; w++)
          Row(
            children: [
              for (var d = 0; d < 7; d++)
                Expanded(
                  child: Builder(builder: (context) {
                    final day = first.addDays(w * 7 + d);
                    final inMonth = day.month == _month.month;
                    final selected = day == widget.initial;
                    final isToday = day == today;
                    return DPressable(
                      id: 'picker.date.${day.iso}',
                      onTap: () => Navigator.of(context).pop(day),
                      borderRadius: BorderRadius.circular(cell),
                      child: Container(
                        height: cell,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? c.accent : null,
                          shape: BoxShape.circle,
                          border: isToday && !selected ? Border.all(color: c.accent, width: 2) : null,
                        ),
                        child: Text(
                          '${day.day}',
                          style: t.text.label.copyWith(
                            color: selected ? c.onAccent : (inMonth ? c.inkPrimary : c.inkTertiary),
                            fontWeight: selected || isToday ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        SizedBox(height: t.space.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DButton(label: 'Today', tone: DButtonTone.tonal, size: DButtonSize.sm, id: 'picker.date.today', onPressed: () => Navigator.of(context).pop(today)),
            SizedBox(width: t.space.sm),
            DButton(label: 'Tomorrow', tone: DButtonTone.neutral, size: DButtonSize.sm, onPressed: () => Navigator.of(context).pop(today.addDays(1))),
          ],
        ),
      ],
    );
  }
}

/// Picks a time of day (minutes after midnight) with big chips.
Future<int?> pickTime(BuildContext context, {required int initial, String title = 'Pick a time'}) =>
    showDSheet<int>(context, title: title, id: 'picker.time', builder: (_) => _TimePicker(initial: initial));

class _TimePicker extends ConsumerStatefulWidget {
  const _TimePicker({required this.initial});
  final int initial;

  @override
  ConsumerState<_TimePicker> createState() => _TimePickerState();
}

class _TimePickerState extends ConsumerState<_TimePicker> {
  late int _minutes = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final h24 = ref.watch(clock24Provider);
    final hour = _minutes ~/ 60;
    final minute = _minutes % 60;
    final pm = hour >= 12;
    final wall = DateTime(2000, 1, 1, hour, minute);
    void set(int h, int m) => setState(() => _minutes = (h.clamp(0, 23)) * 60 + m.clamp(0, 59));

    final hours = h24 ? List<int>.generate(24, (i) => i) : List<int>.generate(12, (i) => i == 0 ? 12 : i);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatTime(wall, h24: h24), style: t.text.display.copyWith(fontSize: 64 * t.scale)),
        SizedBox(height: t.space.md),
        if (!h24)
          DSegmented<bool>(
            idPrefix: 'picker.time.meridiem',
            options: const [(false, 'AM'), (true, 'PM')],
            value: pm,
            onChanged: (v) => set(v ? (hour % 12) + 12 : hour % 12, minute),
          ),
        SizedBox(height: t.space.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final h in hours)
              DChip(
                id: 'picker.time.h$h',
                label: h24 ? h.toString().padLeft(2, '0') : '$h',
                selected: h24 ? hour == h : (hour % 12 == h % 12),
                onTap: () => set(h24 ? h : (h % 12) + (pm ? 12 : 0), minute),
              ),
          ],
        ),
        SizedBox(height: t.space.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final m in const [0, 5, 10, 15, 20, 30, 40, 45, 50])
              DChip(id: 'picker.time.m$m', label: ':${m.toString().padLeft(2, '0')}', selected: minute == m, onTap: () => set(hour, m)),
          ],
        ),
        SizedBox(height: t.space.lg),
        DButton(label: 'Done', id: 'picker.time.done', expand: true, onPressed: () => Navigator.of(context).pop(_minutes)),
      ],
    );
  }
}
