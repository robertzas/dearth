import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/display_state.dart';
import '../../../app/frame.dart';
import '../../../core/data/household.dart';
import '../../../core/platform/freekiosk.dart';
import '../../../core/platform/system_ui.dart';
import '../../../core/providers.dart';
import '../../../core/sound.dart';
import '../settings_screen.dart';

/// This device's media volume as (level, max), where Dearth can set it.
final mediaVolumeProvider = FutureProvider.autoDispose<(int, int)?>((ref) => mediaVolume());

/// Volume steps a family can tell apart: share of the device's maximum.
const List<(double, String)> kVolumeSteps = [(0, 'Off'), (0.25, 'Quiet'), (0.5, 'Medium'), (0.75, 'Loud'), (1, 'Max')];

/// Per-device display settings (SPEC FR-DEV-05, §11.2 uiScale, §11.6 themes).
/// When it goes idle is in Photo frame & night, with the household's idle
/// settings.
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
        if (!s.isPersonal && ref.watch(hasLightSensorProvider).value == true) const _BrightnessGroup(),
        if (ref.watch(mediaVolumeProvider).value case (final level, final max) when max > 0)
          SettingsGroup(
            title: 'Sound',
            footer: 'Chimes, timers and the Toybox play at this volume. The buttons on the device change it too.',
            children: [
              ChoiceRow<double>(
                title: 'Volume',
                idPrefix: 'device.volume',
                options: kVolumeSteps,
                // The step nearest the device's level (its buttons move it too).
                value: kVolumeSteps.map((s) => s.$1).reduce((a, b) => (a - level / max).abs() <= (b - level / max).abs() ? a : b),
                onChanged: (v) async {
                  await setMediaVolume((v * max).round());
                  ref.invalidate(mediaVolumeProvider);
                  // A chime at the new level, so it can be heard.
                  if (v > 0) unawaited(ref.read(soundProvider).play(Sfx.reminder));
                },
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
            // The activity's orientation is Android's alone (FR-DEV-05).
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              ChoiceRow<String>(
                title: 'Orientation',
                subtitle: s.isPersonal ? 'Rotate follows your rotation lock' : 'Rotate follows the way the screen is turned',
                idPrefix: 'device.orientation',
                options: const [('auto', 'Rotate'), ('landscape', 'Landscape'), ('portrait', 'Portrait')],
                value: const {'landscape', 'portrait'}.contains(s.orientation) ? s.orientation : 'auto',
                onChanged: (v) => patch(const {}, columns: {'orientation': v}),
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
        if (!s.isPersonal && ref.watch(freeKioskProvider).value != null) const _KioskGroup(),
      ],
    );
  }
}

/// Brightness from the light sensor (SPEC FR-DSP-02), with what the sensor
/// sees right now so the family can tell it works.
class _BrightnessGroup extends ConsumerWidget {
  const _BrightnessGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(deviceSettingsProvider);
    final session = ref.watch(sessionProvider);
    final lux = ref.watch(roomProvider.select((r) => r.lux));
    final level = ref.watch(brightnessProvider);
    Future<void> patch(Map<String, Object?> p) => updateDeviceSettings(ref.read(writerProvider), deviceId: session.effectiveDeviceId, current: s, patch: p);
    final now = [
      if (lux != null) 'The room: ${lux < 10 ? lux.toStringAsFixed(1) : lux.round()} lux',
      if (level != null) 'the screen at ${(level * 100).round()} %',
    ].join(' · ');
    return SettingsGroup(
      title: 'Brightness',
      footer: [
        if (s.brightness == 'auto') 'Dims with the room’s light, and lower still for the photo frame and at night.' else 'Android sets it by day; the night clock is always dim.',
        if (now.isNotEmpty) '${now[0].toUpperCase()}${now.substring(1)}.',
      ].join(' '),
      children: [
        ChoiceRow<String>(
          title: 'Brightness',
          idPrefix: 'device.brightness',
          options: const [('auto', 'Follow the room'), ('system', 'Android’s')],
          value: s.brightness == 'system' ? 'system' : 'auto',
          onChanged: (v) => patch({'brightness': v}),
        ),
        if (s.brightness != 'system')
          ChoiceRow<int>(
            title: 'Level',
            idPrefix: 'device.bias',
            options: const [(-1, 'Dimmer'), (0, 'Normal'), (1, 'Brighter')],
            value: s.brightnessBias.clamp(-1, 1),
            onChanged: (v) => patch({'brightnessBias': v}),
          ),
      ],
    );
  }
}

/// FreeKiosk, on frames that run it (SPEC §13.9): whether Dearth can reach
/// it, and restarting the frame.
class _KioskGroup extends ConsumerWidget {
  const _KioskGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final status = ref.watch(freeKioskStatusProvider);
    final (link, info) = status.value ?? (FreeKioskLink.unknown, null);
    final subtitle = switch (link) {
      _ when status.isLoading => 'Checking…',
      FreeKioskLink.ok => 'Connected${info?.model == null ? '' : ' · ${info!.model}'} · can turn the screen off at night',
      FreeKioskLink.unauthorized => 'FreeKiosk has another key. Run tool/deploy_frame.sh again and follow its note.',
      FreeKioskLink.unreachable => 'Not answering. Its REST API may be off: run tool/deploy_frame.sh again.',
      FreeKioskLink.unknown => 'Not checked yet',
    };
    return SettingsGroup(
      title: 'Kiosk',
      children: [
        DListRow(
          id: 'device.kiosk',
          title: 'FreeKiosk',
          subtitle: subtitle,
          leading: Icon(Icons.circle, size: 14 * t.scale, color: link == FreeKioskLink.ok ? t.colors.success : t.colors.warning),
          onTap: () => ref.invalidate(freeKioskStatusProvider),
        ),
        if (link == FreeKioskLink.ok)
          DListRow(
            id: 'device.reboot',
            title: 'Restart this frame',
            subtitle: 'Back in about a minute',
            leading: Icon(Icons.restart_alt_rounded, color: t.colors.inkSecondary),
            onTap: () async {
              final ok = await confirmDialog(context, title: 'Restart this frame?', message: 'The screen goes dark for about a minute, then Dearth comes back.', confirmLabel: 'Restart');
              if (!ok) return;
              try {
                await ref.read(freeKioskProvider).value?.reboot();
              } on FreeKioskException catch (e) {
                ref.read(toastProvider).show('FreeKiosk didn’t restart it (${e.link.name})', emoji: '⚠️', tone: DBannerTone.warning);
              }
            },
          ),
      ],
    );
  }
}
