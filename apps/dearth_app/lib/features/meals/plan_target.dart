import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/format.dart';

/// Asks where a recipe goes in the plan: a slot and one of the next two
/// weeks' days, each showing what that slot already holds.
Future<(LocalDate, String)?> pickPlanTarget(BuildContext context, {String title = 'Add to plan', LocalDate? from}) =>
    showDSheet<(LocalDate, String)>(context, id: 'plantarget.sheet', title: title, builder: (_) => _PlanTarget(from: from));

class _PlanTarget extends ConsumerStatefulWidget {
  const _PlanTarget({this.from});
  final LocalDate? from;

  @override
  ConsumerState<_PlanTarget> createState() => _PlanTargetState();
}

class _PlanTargetState extends ConsumerState<_PlanTarget> {
  String? _slot;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final today = ref.watch(todayProvider);
    final slots = ref.watch(mealSlotsProvider);
    final slot = _slot ?? (slots.any((s) => s.$1 == 'dinner') ? 'dinner' : slots.last.$1);
    final from = widget.from;
    final range = DayRange(from != null && from.isAfter(today) ? from : today, 14);
    final meals = ref.watch(mealsInRangeProvider(range)).value ?? const <PlannedMeal>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DSegmented<String>(
          options: [for (final s in slots) (s.$1, s.$2)],
          value: slot,
          idPrefix: 'plantarget.slot',
          onChanged: (v) => setState(() => _slot = v),
        ),
        SizedBox(height: t.space.sm),
        for (final d in range.dates)
          DListRow(
            id: 'plantarget.day.${d.iso}',
            dense: true,
            title: '${relativeDayName(d, today)} · ${monthDay(d)}',
            subtitle: _planned(meals, d, slot) ?? 'Nothing planned',
            trailing: Icon(Icons.add_circle_outline_rounded, color: t.colors.accent),
            onTap: () => Navigator.of(context).pop((d, slot)),
          ),
      ],
    );
  }

  static String? _planned(List<PlannedMeal> meals, LocalDate d, String slot) {
    final titles = [for (final m in meals) if (m.entry.date == d.iso && m.entry.slot == slot) m.title];
    return titles.isEmpty ? null : titles.join(', ');
  }
}
