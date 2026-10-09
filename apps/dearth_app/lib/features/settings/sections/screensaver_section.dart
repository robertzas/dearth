import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/household.dart';
import '../../../core/providers.dart';
import '../settings_screen.dart';

/// The photo frame and the night (SPEC FR-SSV-01…05, FR-DSP-01): what this
/// display does when it's left alone, then what every display shows.
class ScreensaverSection extends ConsumerWidget {
  const ScreensaverSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ss = ref.watch(settingMapProvider(SettingKeys.screensaver));
    final night = ref.watch(settingMapProvider(SettingKeys.nightSchedule));
    final device = ref.watch(deviceSettingsProvider);
    final session = ref.watch(sessionProvider);
    final w = ref.read(writerProvider);
    Future<void> setSs(Map<String, Object?> patch) => w.commit([settingOp(w, SettingKeys.screensaver, {...ss, ...patch})]);
    Future<void> setNight(Map<String, Object?> patch) => w.commit([settingOp(w, SettingKeys.nightSchedule, {...night, ...patch})]);
    Future<void> setDevice(Map<String, Object?> patch) => updateDeviceSettings(w, deviceId: session.effectiveDeviceId, current: device, patch: patch);
    bool flag(String k) => ss[k] as bool? ?? true;
    final usual = (ss['idleMinutes'] as num?)?.toInt() ?? 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Phones and laptops have their own sleep: no photo frame there.
        if (!device.isPersonal)
          SettingsGroup(
            title: 'This display',
            children: [
              DSwitchRow(
                id: 'device.screensaver',
                title: 'Photo frame when idle',
                value: device.screensaver,
                onChanged: (v) => setDevice({'screensaver': v}),
              ),
              ChoiceRow<int?>(
                title: 'Start after',
                subtitle: 'Usual is $usual min, the same on every display',
                idPrefix: 'device.idle',
                options: const [(null, 'Usual'), (2, '2 min'), (5, '5 min'), (10, '10 min'), (30, '30 min')],
                value: device.idleMinutes,
                onChanged: (v) => setDevice({'idleMinutes': v}),
              ),
              DSwitchRow(
                id: 'device.night',
                title: 'Night clock',
                subtitle: 'Dim and warm during the night schedule below',
                value: device.nightMode,
                onChanged: (v) => setDevice({'nightMode': v}),
              ),
              DSwitchRow(
                id: 'device.keepawake',
                title: 'Keep the screen on',
                value: device.keepAwake,
                onChanged: (v) => setDevice({'keepAwake': v}),
              ),
            ],
          ),
        SettingsGroup(
          title: 'Every display',
          footer: 'Photos come from Settings → Photos.',
          children: [
            ChoiceRow<int>(
              title: 'Usually start after',
              idPrefix: 'ss.idle',
              options: const [(2, '2 min'), (5, '5 min'), (10, '10 min'), (30, '30 min')],
              value: usual,
              onChanged: (v) => setSs({'idleMinutes': v}),
            ),
            ChoiceRow<int>(
              title: 'Each photo',
              idPrefix: 'ss.seconds',
              options: const [(10, '10 s'), (30, '30 s'), (60, '1 min'), (120, '2 min')],
              value: (ss['photoSeconds'] as num?)?.toInt() ?? 30,
              onChanged: (v) => setSs({'photoSeconds': v}),
            ),
            DSwitchRow(id: 'ss.clock', title: 'Clock and date', value: flag('clock'), onChanged: (v) => setSs({'clock': v})),
            DSwitchRow(id: 'ss.weather', title: 'Current weather', value: flag('weather'), onChanged: (v) => setSs({'weather': v})),
            DSwitchRow(id: 'ss.next', title: 'Next event', value: flag('nextEvent'), onChanged: (v) => setSs({'nextEvent': v})),
            DSwitchRow(id: 'ss.caption', title: 'Photo captions', value: flag('caption'), onChanged: (v) => setSs({'caption': v})),
            DSwitchRow(
              id: 'ss.kenburns',
              title: 'Slow pan and zoom',
              subtitle: 'Off by default on low-power displays',
              value: ss['kenBurns'] as bool? ?? false,
              onChanged: (v) => setSs({'kenBurns': v}),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Night',
          footer: 'During the night schedule, wall displays show a dim, warm clock.',
          children: [
            DSwitchRow(id: 'night.enabled', title: 'Night schedule', value: night['enabled'] as bool? ?? true, onChanged: (v) => setNight({'enabled': v})),
            ChoiceRow<String>(
              title: 'Starts',
              idPrefix: 'night.start',
              options: const [('20:00', '8 PM'), ('21:00', '9 PM'), ('22:00', '10 PM'), ('23:00', '11 PM')],
              value: night['start'] as String? ?? '21:00',
              onChanged: (v) => setNight({'start': v}),
            ),
            ChoiceRow<String>(
              title: 'Ends',
              idPrefix: 'night.end',
              options: const [('05:30', '5:30'), ('06:30', '6:30'), ('07:00', '7:00'), ('07:30', '7:30')],
              value: night['end'] as String? ?? '06:30',
              onChanged: (v) => setNight({'end': v}),
            ),
          ],
        ),
      ],
    );
  }
}
