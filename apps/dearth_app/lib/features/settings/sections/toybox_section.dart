import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/grown_up.dart';
import '../../../core/data/household.dart';
import '../../toybox/toybox_data.dart';
import '../settings_screen.dart';

/// Toybox (SPEC FR-TOY-04/05): which games are on, how long and when kids
/// can play, how loud, and levels a grown-up wants to hold. Every change
/// needs a grown-up.
class ToyboxSection extends ConsumerStatefulWidget {
  const ToyboxSection({super.key});

  @override
  ConsumerState<ToyboxSection> createState() => _ToyboxSectionState();
}

class _ToyboxSectionState extends ConsumerState<ToyboxSection> {
  String? _kid;

  Future<void> _save(ToyboxSettings Function(ToyboxSettings s) change) async {
    if (!await ensureGrownUp(context, ref, reason: 'The Toybox settings are for grown-ups')) return;
    await saveToyboxSettings(ref, change(ref.read(toyboxSettingsProvider)));
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final s = ref.watch(toyboxSettingsProvider);
    final kids = ref.watch(kidsProvider);
    final kid = kids.where((k) => k.id == _kid).firstOrNull ?? kids.firstOrNull;
    final months = kid == null ? 0 : ref.watch(kidMonthsProvider(kid.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Time',
          footer: 'When time runs out, a game says goodnight and the Toybox sleeps until tomorrow. Kids get a two-minute warning.',
          children: [
            ChoiceRow<int?>(
              title: 'Each day',
              idPrefix: 'toybox.budget',
              options: const [(null, 'No limit'), (15, '15 min'), (30, '30 min'), (45, '45 min'), (60, '1 hour')],
              value: s.budgetMinutes,
              onChanged: (v) => _save((s) => s.copyWith(budgetMinutes: () => v)),
            ),
            ChoiceRow<(String?, String?)>(
              title: 'Open',
              subtitle: 'Closes at bedtime',
              idPrefix: 'toybox.hours',
              options: const [((null, null), 'Any time'), (('07:00', '19:00'), '7 am – 7 pm'), (('08:00', '18:00'), '8 am – 6 pm'), (('09:00', '17:00'), '9 am – 5 pm')],
              value: (s.opens, s.closes),
              onChanged: (v) => _save((s) => s.copyWith(hours: v)),
            ),
            ChoiceRow<double>(
              title: 'Volume',
              idPrefix: 'toybox.volume',
              options: const [(0, 'Silent'), (0.4, 'Quiet'), (0.7, 'Medium'), (1, 'Full')],
              value: const [0.0, 0.4, 0.7, 1.0].reduce((a, b) => (a - s.volume).abs() < (b - s.volume).abs() ? a : b),
              onChanged: (v) => _save((s) => s.copyWith(volume: v)),
            ),
          ],
        ),
        if (kid != null) ...[
          if (kids.length > 1)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DSegmented<String>(idPrefix: 'toybox.kid', options: [for (final k in kids) (k.id, k.name)], value: kid.id, onChanged: (v) => setState(() => _kid = v)),
              ),
            ),
          SettingsGroup(
            title: '${kid.name}’s games',
            footer: 'Kids see the games that suit their age. Switch one off to hide it, or on to let them try it early.',
            children: [
              for (final g in kGames)
                _GameSwitch(game: g, kid: kid, months: months, settings: s, onChanged: (on) => _save((s) => s.withGame(kid.id, g.id, on: on, suits: g.minMonths <= months))),
            ],
          ),
          SettingsGroup(
            title: '${kid.name}’s levels',
            footer: 'Games move up after three wins in a row and ease off after three misses. Pin a level to hold it.',
            children: [
              for (final g in kGames)
                ChoiceRow<int?>(
                  title: '${g.emoji} ${g.title}',
                  subtitle: 'Now at level ${ref.watch(gameLevelProvider((kid.id, g.id)))} of ${g.levels}',
                  idPrefix: 'toybox.pin.${g.id}',
                  options: [(null, 'Auto'), for (var l = 1; l <= g.levels; l++) (l, '$l')],
                  value: s.pinFor(kid.id, g.id),
                  onChanged: (v) => _save((s) {
                    final pins = {...s.pins}..remove('${kid.id}.${g.id}');
                    if (v != null) pins['${kid.id}.${g.id}'] = v;
                    return s.copyWith(pins: pins);
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A game's switch for one kid: on when they see it in their Toybox.
class _GameSwitch extends StatelessWidget {
  const _GameSwitch({required this.game, required this.kid, required this.months, required this.settings, required this.onChanged});
  final GameInfo game;
  final Profile kid;
  final int months;
  final ToyboxSettings settings;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final suits = game.minMonths <= months;
    final on = suits ? !settings.offFor(kid.id).contains(game.id) : settings.earlyFor(kid.id).contains(game.id);
    final age = '${game.minMonths ~/ 12}${game.minMonths % 12 == 6 ? '½' : ''}+';
    return DSwitchRow(
      id: 'toybox.on.${game.id}',
      leading: DEmoji(game.emoji, size: 28 * t.scale),
      title: game.title,
      subtitle: '$age · ${game.skills.join(', ')}${suits ? '' : (on ? ' · opened early' : ' · when ${kid.name} is older')}',
      value: on,
      onChanged: onChanged,
    );
  }
}
