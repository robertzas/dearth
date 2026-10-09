import 'dart:async';

import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/clock_check.dart';

/// "Setting the time…" over everything until the clock can be believed
/// ([ClockCheck]): a frame back from a power cut starts at 1970 for the
/// seconds it takes the network to set it, and every date on screen would
/// be wrong. Touches stop here, so nothing is written with that clock.
class ClockLayer extends ConsumerWidget {
  const ClockLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(clockSetProvider)) return const SizedBox.shrink();
    return const _SettingTheTime();
  }
}

class _SettingTheTime extends ConsumerStatefulWidget {
  const _SettingTheTime();

  @override
  ConsumerState<_SettingTheTime> createState() => _SettingTheTimeState();
}

class _SettingTheTimeState extends ConsumerState<_SettingTheTime> {
  // After a minute the network should have answered: say what to check.
  bool _long = false;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _wait = Timer(const Duration(minutes: 1), () {
      if (mounted) setState(() => _long = true);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final check = ref.read(clockSetProvider.notifier);
    return Material(
      color: t.colors.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(t.space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DEmoji('⏰', size: 96 * t.scale),
                SizedBox(height: t.space.lg),
                tid('clock.setting', Text('Setting the time…', style: t.text.h1, textAlign: TextAlign.center)),
                SizedBox(height: t.space.sm),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560 * t.scale),
                  child: Text(
                    _long
                        ? 'Still waiting for the time. Check that Wi-Fi is on and that this display can reach the internet.'
                        : 'This display lost track of the time. It’s asking the internet, which takes a few seconds once Wi-Fi is on.',
                    style: t.text.body.copyWith(color: t.colors.inkSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
                // A clock set back on purpose (not one stuck in 1970).
                if (_long && check.canAccept) ...[
                  SizedBox(height: t.space.lg),
                  DButton(label: 'The time is right', tone: DButtonTone.outline, id: 'clock.accept', onPressed: check.accept),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
