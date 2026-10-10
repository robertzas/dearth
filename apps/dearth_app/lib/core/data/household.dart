import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

// ─────────────────────────────── Household ──────────────────────────────────

/// Read once in main() so the first frame already has the right time zone.
final initialHouseholdProvider = Provider<Household?>((ref) => null);

final householdProvider = StreamProvider<Household?>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.households)..where((h) => h.id.equals(Ids.household))).watchSingleOrNull();
});

Household? _household(Ref ref) => ref.watch(householdProvider).value ?? ref.watch(initialHouseholdProvider);

/// The family's clock (SPEC §8.3): every "today" decision goes through it.
final householdTimeProvider = Provider<HouseholdTime>((ref) {
  final tz = ref.watch(householdProvider.select((h) => h.value?.timezone)) ?? ref.watch(initialHouseholdProvider)?.timezone;
  final clock = ref.watch(appClockProvider);
  return HouseholdTime.named(tz ?? 'UTC', clock: clock.now);
});

/// Household-local date, updating at midnight only.
final todayProvider = Provider<LocalDate>((ref) {
  ref.watch(minuteProvider);
  return ref.watch(householdTimeProvider).today();
});

final imperialProvider = Provider<bool>((ref) => (_household(ref)?.units ?? 'imperial') == 'imperial');
final clock24Provider = Provider<bool>((ref) => _household(ref)?.clock24 ?? false);

/// ISO weekday the week starts on (7 = Sunday).
final weekStartProvider = Provider<int>((ref) => _household(ref)?.weekStart ?? 7);

/// Household location for solar math and weather, or null.
final householdLocationProvider = Provider<(double, double)?>((ref) {
  final h = _household(ref);
  return h?.lat == null || h?.lon == null ? null : (h!.lat!, h.lon!);
});

// ──────────────────────────────── People ────────────────────────────────────

final profilesProvider = StreamProvider<List<Profile>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.profiles)
        ..where((p) => p.deleted.equals(false) & p.archived.equals(false))
        ..orderBy([(p) => OrderingTerm.asc(p.sortKey), (p) => OrderingTerm.asc(p.name)]))
      .watch();
});

final profileMapProvider = Provider<Map<String, Profile>>((ref) => {for (final p in ref.watch(profilesProvider).value ?? const <Profile>[]) p.id: p});

/// People who appear on calendars and charts (pets included, guests not).
final familyProvider = Provider<List<Profile>>((ref) => [
      for (final p in ref.watch(profilesProvider).value ?? const <Profile>[])
        if (p.role != ProfileRole.guest) p,
    ]);

final kidsProvider = Provider<List<Profile>>((ref) => [
      for (final p in ref.watch(profilesProvider).value ?? const <Profile>[])
        if (p.role == ProfileRole.child) p,
    ]);

/// Lower-case names and nicknames → profile id, for quick add (FR-CAL-12).
final peopleWordsProvider = Provider<Map<String, String>>((ref) {
  final out = <String, String>{};
  for (final p in ref.watch(profilesProvider).value ?? const <Profile>[]) {
    for (final w in [p.name, p.nickname]) {
      if (w == null || w.trim().isEmpty) continue;
      out[w.trim().toLowerCase()] = p.id;
    }
  }
  return out;
});

// ─────────────────────────────── Settings ───────────────────────────────────

/// A household setting's decoded JSON value (null when unset).
final settingProvider = StreamProvider.family<Object?, String>((ref, key) {
  final db = ref.watch(dbProvider);
  return (db.select(db.settings)..where((s) => s.id.equals(Ids.setting('household', key))))
      .watchSingleOrNull()
      .map((s) => s == null || s.deleted ? null : _decode(s.value));
});

Object? _decode(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return raw;
  }
}

/// A household setting whose value is a JSON object ({} when unset).
final settingMapProvider = Provider.family<Map<String, Object?>, String>((ref, key) {
  final v = ref.watch(settingProvider(key)).value;
  return v is Map<String, Object?> ? v : const {};
});

/// Op for writing a household setting (values are stored as JSON).
Op settingOp(DataWriter w, String key, Object? value) =>
    w.op('settings', Ids.setting('household', key), {'scope': 'household', 'key': key, 'value': jsonEncode(value)});

// ───────────────────────────── This device ──────────────────────────────────

final thisDeviceProvider = StreamProvider<Device?>((ref) {
  final db = ref.watch(dbProvider);
  final id = ref.watch(sessionProvider.select((s) => s.effectiveDeviceId));
  return (db.select(db.devices)..where((d) => d.id.equals(id))).watchSingleOrNull();
});

/// Per-device display preferences (synced on the `devices` row so the admin
/// can adjust a frame remotely; SPEC FR-DEV-05).
@immutable
class DeviceSettings {
  const DeviceSettings({
    this.role = DeviceRole.kitchen,
    this.name = 'This display',
    this.orientation = 'auto',
    this.diagonalIn,
    this.viewingDistance = 'room',
    this.tierOverride,
    this.theme = 'auto',
    this.userScale = 1.0,
    this.idleMinutes,
    this.screensaver = true,
    this.nightMode = true,
    this.keepAwake = true,
    this.reducedMotion = false,
    this.brightness = 'auto',
    this.brightnessBias = 0,
    this.nightScreen = 'clock',
    this.darkRoomNight = false,
    this.updates = 'manual',
  });

  factory DeviceSettings.fromRow(Device? d, {String? sessionRole}) {
    final s = decodeJsonMap(d?.settings);
    return DeviceSettings(
      role: d?.role ?? sessionRole ?? DeviceRole.kitchen,
      name: d?.name ?? 'This display',
      orientation: d?.orientation ?? 'auto',
      diagonalIn: d?.diagonalIn,
      viewingDistance: d?.viewingDistance ?? 'room',
      tierOverride: d?.tierOverride,
      theme: s['theme'] as String? ?? 'auto',
      userScale: (s['scale'] as num?)?.toDouble() ?? 1.0,
      idleMinutes: (s['idleMinutes'] as num?)?.toInt(),
      screensaver: s['screensaver'] as bool? ?? true,
      nightMode: s['nightMode'] as bool? ?? true,
      keepAwake: s['keepAwake'] as bool? ?? true,
      reducedMotion: s['reducedMotion'] as bool? ?? false,
      brightness: s['brightness'] as String? ?? 'auto',
      brightnessBias: (s['brightnessBias'] as num?)?.toInt() ?? 0,
      nightScreen: s['nightScreen'] as String? ?? 'clock',
      darkRoomNight: s['darkRoomNight'] as bool? ?? false,
      updates: s['updates'] as String? ?? 'manual',
    );
  }

  final String role;
  final String name;
  final String orientation;
  final double? diagonalIn;
  final String viewingDistance;
  final String? tierOverride;

  /// auto | light | evening | night
  final String theme;
  final double userScale;

  /// Overrides the household screensaver timeout on this device.
  final int? idleMinutes;
  final bool screensaver;
  final bool nightMode;
  final bool keepAwake;
  final bool reducedMotion;

  /// auto (follows the light sensor, FR-DSP-02) | system (Android's).
  final String brightness;

  /// −1 dimmer, 0, +1 brighter, along the auto curve.
  final int brightnessBias;

  /// What the night schedule shows when [nightMode] is on: clock | off
  /// (the screen off until the schedule ends, FR-DSP-03).
  final String nightScreen;

  /// Night also when the room goes dark (§10.12), by the light sensor.
  final bool darkRoomNight;

  /// When a new release installs itself (SPEC §15.3): manual (a grown-up
  /// taps Install) | nightly | idle. Only where it can install silently.
  final String updates;

  bool get isPersonal => role == DeviceRole.personal;

  Map<String, Object?> settingsJson() => {
        'theme': theme,
        'scale': userScale,
        'idleMinutes': ?idleMinutes,
        'screensaver': screensaver,
        'nightMode': nightMode,
        'keepAwake': keepAwake,
        'reducedMotion': reducedMotion,
        'brightness': brightness,
        'brightnessBias': brightnessBias,
        'nightScreen': nightScreen,
        'darkRoomNight': darkRoomNight,
        'updates': updates,
      };

  @override
  bool operator ==(Object other) =>
      other is DeviceSettings &&
      other.role == role &&
      other.name == name &&
      other.orientation == orientation &&
      other.diagonalIn == diagonalIn &&
      other.viewingDistance == viewingDistance &&
      other.tierOverride == tierOverride &&
      other.theme == theme &&
      other.userScale == userScale &&
      other.idleMinutes == idleMinutes &&
      other.screensaver == screensaver &&
      other.nightMode == nightMode &&
      other.keepAwake == keepAwake &&
      other.reducedMotion == reducedMotion &&
      other.brightness == brightness &&
      other.brightnessBias == brightnessBias &&
      other.nightScreen == nightScreen &&
      other.darkRoomNight == darkRoomNight &&
      other.updates == updates;

  @override
  int get hashCode => Object.hash(role, name, orientation, diagonalIn, viewingDistance, tierOverride, theme, userScale, idleMinutes, screensaver, nightMode, keepAwake, reducedMotion, brightness,
      brightnessBias, nightScreen, darkRoomNight, updates);
}

final deviceSettingsProvider = Provider<DeviceSettings>((ref) {
  final role = ref.watch(sessionProvider.select((s) => s.role));
  return DeviceSettings.fromRow(ref.watch(thisDeviceProvider).value, sessionRole: role);
});

/// Writes this device's row: settings JSON merged with [patch], plus any
/// direct [columns] (name, role, diagonal_in, viewing_distance…).
Future<void> updateDeviceSettings(
  DataWriter writer, {
  required String deviceId,
  required DeviceSettings current,
  Map<String, Object?> patch = const {},
  Map<String, Object?> columns = const {},
}) =>
    writer.upsert('devices', deviceId, {
      ...columns,
      if (patch.isNotEmpty) 'settings': {...current.settingsJson(), ...patch},
    });

// ──────────────────────────────── Weather ───────────────────────────────────

/// The Hub-written merged weather report (SPEC §13.4), decoded once.
final weatherProvider = StreamProvider<WeatherReport?>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.weatherReports)..where((w) => w.id.equals(Ids.weather)))
      .watchSingleOrNull()
      .map((r) => r == null || r.deleted ? null : WeatherReport.tryDecode(r.data));
});
