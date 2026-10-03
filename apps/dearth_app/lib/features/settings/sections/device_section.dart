import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/display_state.dart';
import '../../../core/data/household.dart';
import '../../../core/providers.dart';
import '../settings_screen.dart';

/// Per-device display settings (SPEC FR-DEV-05, §11.2 uiScale, §11.6 themes).
class DeviceSection extends ConsumerWidget {
  const DeviceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final s = ref.watch(deviceSettingsProvider);
    final session = ref.watch(sessionProvider);
    final tier = ref.watch(perfTierProvider);
    final writer = ref.read(writerProvider);
    Future<void> patch(Map<String, Object?> p, {Map<String, Object?> columns = const {}}) =>
        updateDeviceSettings(writer, deviceId: session.effectiveDeviceId, current: s, patch: p, columns: columns);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Look',
          children: [
            ChoiceRow<String>(
              title: 'Theme',
              subtitle: 'Auto follows sunset and the night schedule',
              idPrefix: 'device.theme',
              options: const [('auto', 'Auto'), ('light', 'Light'), ('evening', 'Evening'), ('night', 'Night')],
              value: s.theme,
              onChanged: (v) => patch({'theme': v}),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Size', style: t.text.body.copyWith(fontWeight: FontWeight.w600))),
                      tid('device.scale.value', Text('${(s.userScale * 100).round()}%', style: t.text.label)),
                    ],
                  ),
                  Semantics(
                    identifier: 'device.scale',
                    child: Slider(
                      value: s.userScale.clamp(0.8, 1.4),
                      min: 0.8,
                      max: 1.4,
                      divisions: 12,
                      onChanged: (v) => patch({'scale': (v * 100).round() / 100}),
                    ),
                  ),
                ],
              ),
            ),
            ChoiceRow<String>(
              title: 'Viewing distance',
              subtitle: 'How far people usually stand from this screen',
              idPrefix: 'device.distance',
              options: const [('near', 'Near'), ('room', 'Room'), ('far', 'Across')],
              value: s.viewingDistance,
              onChanged: (v) => patch(const {}, columns: {'viewing_distance': v}),
            ),
            DSwitchRow(
              id: 'device.reducedmotion',
              title: 'Reduce motion',
              subtitle: 'Short fades instead of animations',
              value: s.reducedMotion,
              onChanged: (v) => patch({'reducedMotion': v}),
            ),
          ],
        ),
        if (!s.isPersonal)
          SettingsGroup(
            title: 'Idle',
            children: [
              DSwitchRow(
                id: 'device.screensaver',
                title: 'Photo frame when idle',
                value: s.screensaver,
                onChanged: (v) => patch({'screensaver': v}),
              ),
              ChoiceRow<int?>(
                title: 'Start after',
                idPrefix: 'device.idle',
                options: const [(null, 'Household'), (2, '2 min'), (5, '5 min'), (10, '10 min'), (30, '30 min')],
                value: s.idleMinutes,
                onChanged: (v) => patch({'idleMinutes': v}),
              ),
              DSwitchRow(
                id: 'device.night',
                title: 'Night mode',
                subtitle: 'Dim, warm clock during the night schedule',
                value: s.nightMode,
                onChanged: (v) => patch({'nightMode': v}),
              ),
              DSwitchRow(
                id: 'device.keepawake',
                title: 'Keep the screen on',
                value: s.keepAwake,
                onChanged: (v) => patch({'keepAwake': v}),
              ),
            ],
          ),
        SettingsGroup(
          title: 'This device',
          footer: 'Performance tier ${tier.name.toUpperCase()} · role ${s.role}',
          children: [
            ChoiceRow<String>(
              title: 'Role',
              subtitle: 'Kitchen displays get the full experience; phones the companion layout',
              idPrefix: 'device.role',
              options: const [(DeviceRole.kitchen, 'Kitchen'), (DeviceRole.entry, 'Entry'), (DeviceRole.personal, 'Personal')],
              value: const {DeviceRole.kitchen, DeviceRole.entry, DeviceRole.personal}.contains(s.role) ? s.role : DeviceRole.kitchen,
              onChanged: (v) async {
                await patch(const {}, columns: {'role': v});
                await ref.read(sessionProvider.notifier).set(session.copyWith(role: v));
              },
            ),
            ChoiceRow<String?>(
              title: 'Effects',
              subtitle: 'Auto picks from this device’s memory and graphics',
              idPrefix: 'device.tier',
              options: const [(null, 'Auto'), ('t1', 'Light'), ('t2', 'Balanced'), ('t3', 'Full')],
              value: s.tierOverride,
              onChanged: (v) => patch(const {}, columns: {'tier_override': v}),
            ),
          ],
        ),
      ],
    );
  }
}
