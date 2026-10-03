import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/display_state.dart';
import '../../core/data/household.dart';
import '../../core/providers.dart';

/// Cook mode (SPEC FR-RCP-07): one step at a time in large type, the screen
/// kept awake (no screensaver), timers found in the step text ("bake 25
/// minutes") as tap-to-start chips, and the step's ingredients highlighted.
Future<void> openCookMode(BuildContext context, RecipeData recipe, {required int servings}) {
  final t = DTheme.of(context);
  return Navigator.of(context, rootNavigator: true).push<void>(PageRouteBuilder<void>(
    transitionDuration: t.motion(DMotion.standard),
    reverseTransitionDuration: t.motion(DMotion.fast),
    pageBuilder: (_, _, _) => CookMode(recipe: recipe, servings: servings),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

/// The ingredients a step mentions: the whole name, its head noun ("rice
/// vinegar" → "vinegar"), or its first word when no other ingredient is
/// named by that word ("chicken" → "chicken thighs", but "rice" → only
/// "rice", not "rice vinegar"). Whole words, plurals included.
List<Ingredient> ingredientsForStep(String step, List<Ingredient> all) {
  final s = step.toLowerCase();
  bool has(String w) => RegExp('\\b${RegExp.escape(w)}(e?s)?\\b').hasMatch(s);
  List<String> words(Ingredient i) => (i.key.isNotEmpty ? i.key : i.name).toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  final heads = {for (final i in all) ...words(i).reversed.take(1)};
  return [
    for (final i in all)
      if (words(i) case final ws when ws.isNotEmpty && (has(ws.join(' ')) || has(ws.last) || (ws.length > 1 && !heads.contains(ws.first) && has(ws.first)))) i,
  ];
}

class _RunningTimer {
  _RunningTimer(this.label, this.seconds, this.endsAtMs);
  final String label;
  final int seconds;
  final int endsAtMs;
}

class CookMode extends ConsumerStatefulWidget {
  const CookMode({super.key, required this.recipe, required this.servings});
  final RecipeData recipe;
  final int servings;

  @override
  ConsumerState<CookMode> createState() => _CookModeState();
}

class _CookModeState extends ConsumerState<CookMode> {
  int _step = 0;
  final _timers = <_RunningTimer>[];
  Timer? _tick;
  late final DisplayController _display = ref.read(displayProvider.notifier);
  late final List<Ingredient> _ingredients = widget.recipe.scaledIngredients(widget.servings);

  List<String> get _steps => widget.recipe.steps;

  @override
  void initState() {
    super.initState();
    _awake();
  }

  @override
  void dispose() {
    _tick?.cancel();
    // Hand the display back to the idle engine.
    _display.keepAwakeFor(Duration.zero);
    super.dispose();
  }

  int _now() => ref.read(appClockProvider).nowMs();

  void _awake([Duration d = const Duration(minutes: 30)]) {
    final longest = _timers.fold<int>(0, (m, x) => x.endsAtMs - _now() > m ? x.endsAtMs - _now() : m);
    _display.keepAwakeFor(Duration(milliseconds: longest) + d);
  }

  void _go(int step) {
    setState(() => _step = step.clamp(0, _steps.length - 1));
    _awake();
  }

  void _startTimer(int seconds, String label) {
    setState(() => _timers.add(_RunningTimer(label, seconds, _now() + seconds * 1000)));
    _awake(const Duration(minutes: 5));
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final now = _now();
    final done = [for (final x in _timers) if (x.endsAtMs <= now) x];
    for (final d in done) {
      ref.read(toastProvider).show('Timer done: ${d.label}', emoji: '⏰', duration: const Duration(seconds: 12), tone: DBannerTone.warning);
    }
    _timers.removeWhere(done.contains);
    if (_timers.isEmpty) {
      _tick?.cancel();
      _tick = null;
    }
    setState(() {});
  }

  void _finish() {
    Navigator.of(context).pop();
    ref.read(toastProvider).show('Enjoy your ${widget.recipe.title}!', emoji: '🍽️');
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final metric = !ref.watch(imperialProvider);
    final n = _steps.length;
    final step = _steps[_step];
    final timers = stepTimers(step);
    final used = ingredientsForStep(step, _ingredients);
    final wide = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height && !t.isPhone;
    final stepView = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step ${_step + 1}', style: t.text.overline.copyWith(color: t.colors.accent)),
        SizedBox(height: t.space.sm),
        tid('cook.step', Text(step, style: (t.isPhone ? t.text.h2 : t.text.h1).copyWith(height: 1.3))),
        if (timers.isNotEmpty) ...[
          SizedBox(height: t.space.lg),
          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: [
              for (final (i, (seconds, label)) in timers.indexed)
                DButton(
                  label: 'Start ${_duration(seconds)} timer',
                  icon: Icons.timer_outlined,
                  tone: DButtonTone.tonal,
                  id: 'cook.timer.$i',
                  onPressed: () => _startTimer(seconds, label),
                ),
            ],
          ),
        ],
      ],
    );
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_timers.isNotEmpty) ...[
          for (final (i, x) in _timers.indexed) _TimerTile(timer: x, nowMs: _now(), id: 'cook.running.$i', onCancel: () => setState(() => _timers.remove(x))),
          SizedBox(height: t.space.md),
        ],
        DCard(
          id: 'cook.ingredients',
          padding: EdgeInsets.all(t.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(used.isEmpty ? 'Ingredients' : 'For this step', style: t.text.title),
              SizedBox(height: t.space.sm),
              for (final i in used.isEmpty ? _ingredients : used)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space.xxs),
                  child: Text(i.describe(metric: metric), style: (used.isEmpty ? t.text.body : t.text.bodyStrong)),
                ),
            ],
          ),
        ),
      ],
    );
    // A Material ancestor gives text its default style (no debug underline)
    // and ink a surface: this route sits above the app shell.
    return tid(
      'screen.cook',
      Material(
        color: t.colors.surface,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(t.pageMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DIconButton(icon: Icons.close_rounded, label: 'Leave cook mode', id: 'cook.close', tone: DButtonTone.ghost, onPressed: () => Navigator.of(context).pop()),
                    SizedBox(width: t.space.sm),
                    Expanded(child: Text(widget.recipe.title, style: t.text.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    tid('cook.progress', Text('Step ${_step + 1} of $n', style: t.text.label.copyWith(color: t.colors.inkSecondary))),
                  ],
                ),
                SizedBox(height: t.space.sm),
                ClipRRect(
                  borderRadius: t.radius.pill,
                  child: SizedBox(
                    height: 6 * t.scale,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: t.colors.surfaceSunken),
                        FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: (_step + 1) / n, child: ColoredBox(color: t.colors.accent)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: t.space.xl),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: SingleChildScrollView(child: stepView)),
                            SizedBox(width: t.gutter * 2),
                            Expanded(flex: 2, child: SingleChildScrollView(child: side)),
                          ],
                        )
                      : ListView(children: [stepView, SizedBox(height: t.space.xl), side]),
                ),
                SizedBox(height: t.space.md),
                Row(
                  children: [
                    DButton(label: 'Back', icon: Icons.arrow_back_rounded, tone: DButtonTone.tonal, size: DButtonSize.lg, id: 'cook.prev', onPressed: _step == 0 ? null : () => _go(_step - 1)),
                    const Spacer(),
                    if (_step < n - 1)
                      DButton(label: 'Next step', trailingIcon: Icons.arrow_forward_rounded, size: DButtonSize.lg, id: 'cook.next', onPressed: () => _go(_step + 1))
                    else
                      DButton(label: 'All done', emoji: '🎉', size: DButtonSize.lg, id: 'cook.done', onPressed: _finish),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _duration(int seconds) {
  if (seconds % 3600 == 0) return '${seconds ~/ 3600} h';
  if (seconds >= 3600) return '${seconds ~/ 3600} h ${(seconds % 3600) ~/ 60} min';
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _TimerTile extends StatelessWidget {
  const _TimerTile({required this.timer, required this.nowMs, required this.id, required this.onCancel});
  final _RunningTimer timer;
  final int nowMs;
  final String id;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final left = ((timer.endsAtMs - nowMs) / 1000).ceil().clamp(0, timer.seconds);
    final mm = (left ~/ 60).toString().padLeft(2, '0'), ss = (left % 60).toString().padLeft(2, '0');
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: DCard(
        id: id,
        semanticLabel: '${timer.label}: $mm:$ss left',
        color: t.colors.accentTint,
        padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        child: Row(
          children: [
            DProgressRing(progress: 1 - left / timer.seconds, size: 36 * t.scale),
            SizedBox(width: t.space.sm),
            Expanded(child: Text(timer.label, style: t.text.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('$mm:$ss', style: t.text.title.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            DIconButton(icon: Icons.close_rounded, label: 'Cancel timer', tone: DButtonTone.ghost, onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}
