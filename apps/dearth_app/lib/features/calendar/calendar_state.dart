import 'package:dearth_core/dearth_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/providers.dart';

/// Calendar views (SPEC FR-CAL-05…09). The People view comes in a one-day
/// and a three-day span; the switcher shows them as one "People" option.
enum CalView {
  day('Day', 1),
  threeDay('3 days', 3),
  week('Week', 7),
  people('People', 1),
  people3('People', 3),
  month('Month', 42),
  agenda('Agenda', 14);

  const CalView(this.label, this.span);
  final String label;
  final int span;

  bool get isPeople => this == people || this == people3;

  /// Day columns on a time grid (everything but month and agenda).
  bool get isGrid => this != month && this != agenda;

  static CalView? parse(String? s) => values.where((v) => v.name == s).firstOrNull;
}

@immutable
class CalNav {
  const CalNav({this.view, required this.anchor});

  /// null = the orientation default (landscape → week, portrait → agenda).
  final CalView? view;
  final LocalDate anchor;

  CalNav copyWith({CalView? view, LocalDate? anchor}) => CalNav(view: view ?? this.view, anchor: anchor ?? this.anchor);
}

/// Which view and date the calendar shows. Shared so Home widgets can open
/// the calendar at a given day.
class CalNavController extends Notifier<CalNav> {
  @override
  CalNav build() {
    final saved = CalView.parse(ref.read(savedCalendarViewProvider));
    return CalNav(view: saved, anchor: ref.read(todayProvider));
  }

  void setView(CalView v) {
    state = state.copyWith(view: v);
    ref.read(dbProvider).kvSet('calendar.view', v.name);
  }

  void show(LocalDate date, {CalView? view}) => state = CalNav(view: view ?? state.view, anchor: date);
  void today() => state = state.copyWith(anchor: ref.read(todayProvider));

  void step(CalView view, int direction) {
    final a = state.anchor;
    state = state.copyWith(
      anchor: switch (view) {
        CalView.month => a.addMonths(direction),
        CalView.agenda => a.addDays(7 * direction),
        _ => a.addDays(view.span * direction),
      },
    );
  }
}

/// The last chosen view, preloaded from the device kv store in main().
final savedCalendarViewProvider = Provider<String?>((ref) => null);

final calNavProvider = NotifierProvider<CalNavController, CalNav>(CalNavController.new);

/// The days a view covers around [anchor].
DayRange visibleRange(CalView view, LocalDate anchor, int weekStart) => switch (view) {
      CalView.day || CalView.people => DayRange(anchor, 1),
      CalView.threeDay || CalView.people3 => DayRange(anchor, 3),
      CalView.week => DayRange(anchor.startOfWeek(weekStart), 7),
      CalView.month => DayRange(anchor.startOfMonth.startOfWeek(weekStart), 42),
      CalView.agenda => DayRange(anchor, 14),
    };
