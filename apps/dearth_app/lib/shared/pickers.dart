import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/data/household.dart';
import '../core/format.dart';

/// Picks a household-local date from a month grid. The month's title opens
/// a grid of years, then of months, so a date decades away is three taps.
/// A [birthday] starts there (an adult's year is far from this one; an
/// unset one starts 30 years back), offers no year after this one, and
/// leaves out Today and Tomorrow.
Future<LocalDate?> pickDate(BuildContext context, {required LocalDate initial, String title = 'Pick a date', bool birthday = false, bool unset = false}) =>
    showDSheet<LocalDate>(context, title: title, id: 'picker.date', builder: (_) => _DatePicker(initial: initial, birthday: birthday, unset: unset));

enum _View { days, months, years }

class _DatePicker extends ConsumerStatefulWidget {
  const _DatePicker({required this.initial, required this.birthday, required this.unset});
  final LocalDate initial;
  final bool birthday;

  /// No date chosen yet: nothing is marked as picked.
  final bool unset;

  @override
  ConsumerState<_DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends ConsumerState<_DatePicker> {
  late LocalDate _month = widget.unset && widget.birthday ? LocalDate(widget.initial.year - 30, 1, 1) : widget.initial.startOfMonth;
  late _View _view = widget.birthday && widget.unset ? _View.years : _View.days;
  ScrollController? _yearScroll;

  @override
  void dispose() {
    _yearScroll?.dispose();
    super.dispose();
  }

  void _show(_View v, [LocalDate? month]) => setState(() {
        _view = v;
        if (month != null) _month = month;
        if (v != _View.years) {
          _yearScroll?.dispose();
          _yearScroll = null;
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final cell = 60 * t.scale;
    return switch (_view) {
      _View.days => _days(context, cell),
      _View.months => _months(context, cell),
      _View.years => _years(context, cell),
    };
  }

  /// The title row: tapping the title steps out to months, then years.
  Widget _header(BuildContext context, String title, {required String id, VoidCallback? onTitle, VoidCallback? onPrev, VoidCallback? onNext, String unit = 'month'}) {
    final t = DTheme.of(context);
    return Row(
      children: [
        if (onPrev != null) DIconButton(icon: Icons.chevron_left_rounded, label: 'Previous $unit', id: 'picker.date.prev', onPressed: onPrev) else SizedBox(width: 48 * t.scale),
        Expanded(
          child: Center(
            child: DPressable(
              id: id,
              semanticLabel: title,
              excludeSemantics: true,
              onTap: onTitle,
              borderRadius: t.radius.pill,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, textAlign: TextAlign.center, style: t.text.title),
                    if (onTitle != null) Icon(Icons.arrow_drop_down_rounded, size: 28 * t.scale, color: t.colors.inkSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onNext != null) DIconButton(icon: Icons.chevron_right_rounded, label: 'Next $unit', id: 'picker.date.next', onPressed: onNext) else SizedBox(width: 48 * t.scale),
      ],
    );
  }

  int get _lastYear => widget.birthday ? ref.read(todayProvider).year : ref.read(todayProvider).year + 20;

  Widget _years(BuildContext context, double cell) {
    final t = DTheme.of(context);
    final c = t.colors;
    final last = _lastYear;
    // Newest first: a kid's year is near the top, a grandparent's a scroll away.
    final years = [for (var y = last; y >= last - 110; y--) y];
    const per = 4;
    final row = cell * 0.9;
    final at = years.indexOf(_month.year).clamp(0, years.length - 1) ~/ per;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, 'Year', id: 'picker.date.title'),
        SizedBox(height: t.space.sm),
        SizedBox(
          height: row * 6.5,
          child: ListView.builder(
            // The chosen year's row in the middle, with rows above it showing.
            controller: _yearScroll ??= ScrollController(initialScrollOffset: ((at - 2) * row).clamp(0, double.infinity)),
            itemExtent: row,
            itemCount: (years.length / per).ceil(),
            itemBuilder: (context, r) => Row(
              children: [
                for (var i = r * per; i < r * per + per; i++)
                  Expanded(
                    child: i >= years.length
                        ? const SizedBox.shrink()
                        : DPressable(
                            id: 'picker.year.${years[i]}',
                            semanticLabel: '${years[i]}',
                            excludeSemantics: true,
                            onTap: () => _show(_View.months, LocalDate(years[i], _month.month, 1)),
                            borderRadius: t.radius.pill,
                            child: Container(
                              height: row * 0.84,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: years[i] == _month.year ? c.accent : null, borderRadius: t.radius.pill),
                              child: Text('${years[i]}', style: t.text.label.copyWith(color: years[i] == _month.year ? c.onAccent : c.inkPrimary, fontWeight: FontWeight.w700)),
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _months(BuildContext context, double cell) {
    final t = DTheme.of(context);
    final c = t.colors;
    final picked = widget.unset ? null : widget.initial;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          context,
          '${_month.year}',
          id: 'picker.date.title',
          unit: 'year',
          onTitle: () => _show(_View.years),
          onPrev: () => setState(() => _month = LocalDate(_month.year - 1, _month.month, 1)),
          onNext: _month.year >= _lastYear ? null : () => setState(() => _month = LocalDate(_month.year + 1, _month.month, 1)),
        ),
        SizedBox(height: t.space.sm),
        for (var r = 0; r < 4; r++)
          Row(
            children: [
              for (var m = r * 3 + 1; m <= r * 3 + 3; m++)
                Expanded(
                  child: Builder(builder: (context) {
                    final month = LocalDate(_month.year, m, 1);
                    final selected = picked != null && picked.year == month.year && picked.month == m;
                    return DPressable(
                      id: 'picker.month.$m',
                      semanticLabel: monthYear(month),
                      excludeSemantics: true,
                      onTap: () => _show(_View.days, month),
                      borderRadius: t.radius.pill,
                      child: Container(
                        height: cell * 1.2,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: selected ? c.accent : null, borderRadius: t.radius.pill),
                        child: Text(monthYear(month).split(' ').first.substring(0, 3), style: t.text.label.copyWith(color: selected ? c.onAccent : c.inkPrimary, fontWeight: FontWeight.w700)),
                      ),
                    );
                  }),
                ),
            ],
          ),
      ],
    );
  }

  Widget _days(BuildContext context, double cell) {
    final t = DTheme.of(context);
    final c = t.colors;
    final weekStart = ref.watch(weekStartProvider);
    final today = ref.watch(todayProvider);
    final first = _month.startOfWeek(weekStart);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          context,
          monthYear(_month),
          id: 'picker.date.title',
          onTitle: () => _show(_View.months),
          onPrev: () => setState(() => _month = _month.addMonths(-1)),
          onNext: () => setState(() => _month = _month.addMonths(1)),
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
                    final selected = !widget.unset && day == widget.initial;
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
        if (!widget.birthday) ...[
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
