import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase;

import 'package:dearth_app/app/app.dart';
import 'package:dearth_app/app/display_state.dart';
import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/env.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_app/features/calendar/calendar_screen.dart';
import 'package:dearth_app/features/calendar/calendar_state.dart';
import 'package:dearth_app/features/toybox/game_host.dart';
import 'package:dearth_app/features/toybox/toybox_screen.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show DemoIds;
import 'package:drift/native.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

/// The frame perf gate's scenarios (SPEC §12.9), run on the device by
/// `tool/perf_gate.sh`: the real app on a demo household, at full motion
/// (not the E2E mode, which turns animations off), with real frames.
/// Each scenario logs one `PERF_RESULT {json}` line; the script reads them
/// from logcat and compares them with the device's baseline.
///
/// Built as the app's entry point (`-t integration_test/perf_test.dart`):
/// FreeKiosk relaunches the app whenever it stops, which `flutter drive`
/// can't live with, so the tests run as soon as the app starts.
/// Frames only when the app asks for them, as on a real display.
///
/// Every live test policy but `benchmark` makes the binding ask the engine
/// for another frame at the end of each one, so a still screen redraws at
/// the display's full rate (Home "idle" measured 41 fps and 26 % CPU; the
/// app itself, 0 %). `benchmark` stops that but drops the app's own
/// requests too, so animations stall. Here the binding runs each frame's
/// draw phase under `benchmark` (no trailing request) and passes on any
/// frame the app asked for meanwhile, once the draw is over.
class _RealFramesBinding extends IntegrationTestWidgetsFlutterBinding {
  bool _drawing = false;
  bool _wanted = false;

  @override
  void scheduleFrame() {
    if (_drawing) {
      _wanted = true;
      return;
    }
    super.scheduleFrame();
  }

  @override
  void handleDrawFrame() {
    _drawing = true;
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
    try {
      super.handleDrawFrame();
    } finally {
      framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
      _drawing = false;
    }
    if (_wanted) {
      _wanted = false;
      scheduleFrame();
    }
  }
}

void main() {
  _RealFramesBinding();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The test's own pumps (inside fling and tap) don't add frames either.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  const soakMinutes = int.fromEnvironment('PERF_SOAK_MINUTES');

  testWidgets('perf gate scenarios', timeout: const Timeout(Duration(minutes: 30 + soakMinutes)), (tester) async {
    try {
      await _run(tester, soakMinutes: soakMinutes);
      debugPrint('PERF_DONE ${jsonEncode({'ok': true})}');
    } on Object catch (e, s) {
      debugPrint('PERF_FAILED $e\n$s');
      rethrow;
    }
  });
}

Future<void> _run(WidgetTester tester, {required int soakMinutes}) async {
  ensureTimeZones();
  _only = _readOnly();
  // A fixed morning, so the night schedule never takes over mid-run.
  final now = DateTime.now();
  final db = DearthDb(NativeDatabase.memory());
  final c = ProviderContainer(overrides: [
    envProvider.overrideWithValue(AppEnv(fakeNow: DateTime(now.year, now.month, now.day, 10))),
    dbProvider.overrideWithValue(db),
    nodeIdProvider.overrideWithValue('dperf'),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const DearthApp()));
  await c.read(sessionProvider.notifier).startDemo();
  await _wait(const Duration(seconds: 5));
  await _seedEvents(c, 300);
  final router = c.read(routerProvider);

  // Home idle: the clock ticks, nothing else should draw.
  router.go('/');
  await _wait(const Duration(seconds: 3));
  await _measure('home_idle', () => _wait(const Duration(seconds: 30)));

  // Every destination, three times.
  const destinations = ['/', '/calendar', '/meals', '/lists', '/kids', '/toybox', '/weather', '/photos', '/settings'];
  // Each frame is also counted under the destination it was drawn for, so
  // the report says which switch got slower.
  final marks = <(int, String)>[];
  await _measure('navigate', marks: marks, () async {
    for (var round = 0; round < 3; round++) {
      for (final d in destinations) {
        marks.add((Timeline.now, d));
        router.go(d);
        await _wait(const Duration(milliseconds: 900));
      }
    }
  });

  // The calendar: agenda fling over 300 events, week paging, month.
  final cal = c.read(calNavProvider.notifier);
  router.go('/calendar');
  cal.setView(CalView.agenda);
  await _wait(const Duration(seconds: 2));
  await _measure('agenda_fling', () async {
    final list = find.descendant(of: find.byType(CalendarScreen), matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 6; i++) {
      await tester.fling(list, Offset(0, i < 4 ? -700 : 700), 2500);
      await _wait(const Duration(milliseconds: 1500));
    }
  });
  cal.setView(CalView.week);
  await _wait(const Duration(seconds: 2));
  await _measure('week_paging', () async {
    for (var i = 0; i < 10; i++) {
      cal.step(CalView.week, i < 5 ? 1 : -1);
      await _wait(const Duration(milliseconds: 700));
    }
  });
  await _measure('month_open', () async {
    for (var i = 0; i < 3; i++) {
      cal.setView(CalView.month);
      await _wait(const Duration(milliseconds: 1500));
      cal.setView(CalView.week);
      await _wait(const Duration(milliseconds: 1500));
    }
  });

  // The Toybox launcher: the screen measured GPU-bound in SPEC §12.2.
  router.go('/toybox');
  await _wait(const Duration(seconds: 2));
  await _measure('toybox_scroll', () async {
    final grid = find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 6; i++) {
      await tester.fling(grid, Offset(0, i < 3 ? -600 : 600), 2000);
      await _wait(const Duration(milliseconds: 1500));
    }
  });

  // Games: particles (Bubble Pop) and strokes (Paint Studio).
  final ava = await (db.select(db.profiles)..where((p) => p.id.equals(DemoIds.ava))).getSingle();
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final rng = math.Random(7);
  Future<void> inGame(String id, Future<void> Function() play) async {
    final navigator = Navigator.of(tester.element(find.byType(ToyboxScreen)), rootNavigator: true);
    unawaited(navigator.push<void>(PageRouteBuilder<void>(pageBuilder: (_, _, _) => GameScreen(game: gameById(id)!, kid: ava))));
    await _wait(const Duration(seconds: 3));
    await _measure(id, play);
    navigator.pop();
    await _wait(const Duration(seconds: 2));
  }

  await inGame('bubbles', () async {
    for (var i = 0; i < 120; i++) {
      await tester.tapAt(Offset(size.width * (0.15 + 0.7 * rng.nextDouble()), size.height * (0.25 + 0.6 * rng.nextDouble())));
      await _wait(const Duration(milliseconds: 150));
    }
  });
  await inGame('paint', () async {
    for (var i = 0; i < 20; i++) {
      final from = Offset(size.width * (0.25 + 0.4 * rng.nextDouble()), size.height * (0.3 + 0.4 * rng.nextDouble()));
      await tester.timedDragFrom(from, Offset(size.width * 0.2 * (rng.nextDouble() - 0.5), size.height * 0.2 * (rng.nextDouble() - 0.5)), const Duration(milliseconds: 1200));
      await _wait(const Duration(milliseconds: 300));
    }
  });

  // The photo frame: a transition every 10 s.
  final w = c.read(writerProvider);
  final ss = c.read(settingMapProvider(SettingKeys.screensaver));
  await w.commit([settingOp(w, SettingKeys.screensaver, {...ss, 'photoSeconds': 10})]);
  router.go('/');
  await _wait(const Duration(seconds: 2));
  c.read(displayProvider.notifier).startScreensaver();
  await _measure('screensaver', () => _wait(const Duration(seconds: 45)));
  c.read(displayProvider.notifier).wake();
  await _wait(const Duration(seconds: 2));

  // Memory over time: destinations on a loop, memory each minute.
  if (soakMinutes > 0 && (_only.isEmpty || _only.contains('soak'))) {
    final rss = <int>[];
    final end = DateTime.now().add(Duration(minutes: soakMinutes));
    var next = DateTime.now();
    while (DateTime.now().isBefore(end)) {
      for (final d in destinations) {
        router.go(d);
        await _wait(const Duration(seconds: 2));
      }
      if (DateTime.now().isAfter(next)) {
        rss.add(ProcessInfo.currentRss ~/ (1 << 20));
        next = next.add(const Duration(minutes: 1));
      }
    }
    debugPrint('PERF_RESULT ${jsonEncode({'name': 'soak', 'minutes': soakMinutes, 'rssMb': rss, 'growthMb': rss.isEmpty ? 0 : rss.last - rss.first})}');
  }
  c.dispose();
}

/// 300 timed events over five weeks around today: 60 a week (SPEC §12.9).
Future<void> _seedEvents(ProviderContainer c, int count) async {
  final time = c.read(householdTimeProvider);
  final w = c.read(writerProvider);
  final today = time.today();
  const titles = ['Swim lesson', 'Dentist', 'Soccer practice', 'Piano', 'Playdate', 'Groceries', 'Library', 'Vet', 'Book club', 'Haircut'];
  await w.commit([
    for (var i = 0; i < count; i++)
      w.op('events', 'perf-$i', {
        'source_id': Ids.familyCalendar,
        'title': titles[i % titles.length],
        'start_ms': time.msAt(today.addDays(i % 35 - 14), 7 + i % 12, (i * 15) % 60),
        'end_ms': time.msAt(today.addDays(i % 35 - 14), 7 + i % 12, (i * 15) % 60) + 45 * 60000,
        'tz': time.zoneName,
        'profile_ids': [if (i.isEven) DemoIds.mom, if (i % 3 == 0) DemoIds.ava],
      }),
  ]);
}

Future<void> _wait(Duration d) => Future<void>.delayed(d);

/// The scenarios to measure, all when empty: `--only` on the script (built
/// in), or the `debug.dearth.perf_only` property (comma-separated), which
/// the script sets to measure a scenario again without a new build.
Set<String> _only = const {};

Set<String> _readOnly() {
  final names = {for (final n in const String.fromEnvironment('PERF_ONLY').split(',')) if (n.isNotEmpty) n};
  try {
    final prop = Process.runSync('getprop', ['debug.dearth.perf_only']).stdout.toString().trim();
    names.addAll([for (final n in prop.split(',')) if (n.trim().isNotEmpty) n.trim()]);
  } on Object {
    // No getprop (not Android): the built-in list only.
  }
  return names;
}

/// Runs [scenario] and logs its frames (build, raster and total time
/// against the display's budget), CPU and memory.
///
/// With [marks] ((Timeline.now, label) at each step, filled while the
/// scenario runs), each frame also counts under the label it started in,
/// reported as `parts`: frames, build p90 and total p90 per label.
Future<void> _measure(String name, Future<void> Function() scenario, {List<(int, String)>? marks}) async {
  if (_only.isNotEmpty && !_only.contains(name)) return;
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(collect);
  final cpu0 = _cpuTicks();
  final sw = Stopwatch()..start();
  await scenario();
  // Timings arrive in batches, up to a second late.
  await _wait(const Duration(milliseconds: 1500));
  sw.stop();
  final cpu1 = _cpuTicks();
  SchedulerBinding.instance.removeTimingsCallback(collect);

  final view = SchedulerBinding.instance.platformDispatcher.views.first;
  final hz = view.display.refreshRate > 0 ? view.display.refreshRate : 60.0;
  final budgetUs = 1e6 / hz;
  List<int> us(int Function(FrameTiming) f) => [for (final t in timings) f(t)]..sort();
  double pct(List<int> v, double p) => v.isEmpty ? 0 : v[math.min(v.length - 1, (v.length * p).floor())] / 1000;
  final build = us((t) => t.buildDuration.inMicroseconds);
  final raster = us((t) => t.rasterDuration.inMicroseconds);
  final total = us((t) => t.totalSpan.inMicroseconds);
  final seconds = sw.elapsedMicroseconds / 1e6;
  final result = {
    'name': name,
    'seconds': double.parse(seconds.toStringAsFixed(1)),
    'frames': timings.length,
    'fps': double.parse((timings.length / seconds).toStringAsFixed(1)),
    'budgetMs': double.parse((budgetUs / 1000).toStringAsFixed(1)),
    'buildP50': pct(build, 0.5), 'buildP90': pct(build, 0.9), 'buildP99': pct(build, 0.99),
    'rasterP50': pct(raster, 0.5), 'rasterP90': pct(raster, 0.9), 'rasterP99': pct(raster, 0.99),
    'totalP90': pct(total, 0.9), 'worstMs': pct(total, 1),
    'jankPct': timings.isEmpty ? 0 : double.parse((100 * total.where((v) => v > budgetUs).length / timings.length).toStringAsFixed(1)),
    'over50': total.where((v) => v > 50000).length,
    if (cpu0 != null && cpu1 != null) 'cpuPct': double.parse((100 * (cpu1 - cpu0) / 100 / seconds / Platform.numberOfProcessors).toStringAsFixed(1)),
    'rssMb': ProcessInfo.currentRss ~/ (1 << 20),
    if (marks != null && marks.isNotEmpty) 'parts': _parts(timings, marks, pct),
  };
  debugPrint('PERF_RESULT ${jsonEncode(result)}');
}

/// [timings] split by the last mark before each frame's build started
/// (FrameTiming stamps share the Timeline clock). Labels that drew nothing
/// are left out; frames before the first mark count under it.
Map<String, Object?> _parts(List<FrameTiming> timings, List<(int, String)> marks, double Function(List<int>, double) pct) {
  final build = <String, List<int>>{}, total = <String, List<int>>{};
  for (final t in timings) {
    final at = t.timestampInMicroseconds(FramePhase.buildStart);
    var label = marks.first.$2;
    for (final (stamp, l) in marks) {
      if (stamp > at) break;
      label = l;
    }
    (build[label] ??= []).add(t.buildDuration.inMicroseconds);
    (total[label] ??= []).add(t.totalSpan.inMicroseconds);
  }
  return {
    for (final label in build.keys)
      label: {'frames': build[label]!.length, 'buildP90': pct(build[label]!..sort(), 0.9), 'totalP90': pct(total[label]!..sort(), 0.9)},
  };
}

/// This process's CPU time in clock ticks (utime + stime, 100 a second on
/// Android), or null where /proc isn't there.
int? _cpuTicks() {
  try {
    final stat = File('/proc/self/stat').readAsStringSync();
    final f = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    return int.parse(f[11]) + int.parse(f[12]);
  } on Object {
    return null;
  }
}
