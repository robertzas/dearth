import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../connections.dart';
import '../integrations.dart';
import 'scheduler.dart';

final _log = Logger('updates');

/// Keeps the Hub on the newest release (SPEC FR-ADM-04, §15.3). Every hour
/// it reads GitHub's latest release; a newer one installs when a grown-up
/// taps Install in Settings → Updates, or by itself nightly (3–5 am
/// household time) or as soon as it's seen, as the household chose
/// ([SettingKeys.hubUpdates]).
///
/// Installing asks the Watchtower beside the Hub (`compose.yml`) to pull
/// the image and recreate the Hub's container: a process can't replace
/// itself. CI moves the image's `latest` tag before it publishes the
/// release, so the image Watchtower finds is the release the Hub saw.
/// Displays reconnect by themselves a few seconds later.
class HubUpdateJob implements HubJob {
  HubUpdateJob(this.integrations, this.config, {String? version, this.installGrace = const Duration(minutes: 15)})
      : versionName = version ?? hubVersion,
        version = AppVersion.tryParse(version ?? hubVersion) {
    _restore();
  }

  final Integrations integrations;
  final HubConfig config;

  /// What the Hub says it is, and the release version in it (null for a
  /// development build, which never updates by itself).
  final String versionName;
  final AppVersion? version;

  /// How long an install may take before the Hub calls it failed (it is
  /// still the one answering).
  final Duration installGrace;

  AppVersion? latest;
  int? checkedAtMs;
  String? error;
  bool installing = false;

  /// Releases that didn't install: never tried again by themselves.
  final Set<AppVersion> _failed = {};
  Timer? _watchdog;

  @override
  String get id => 'hub-update';

  @override
  Duration nextDelay() => const Duration(hours: 1);

  bool get available => latest != null && (version == null || latest! > version!);

  @override
  Future<void> run() async {
    // E2E and demos run without the network.
    if (config.fakeProviders) return;
    await check();
    await _maybeInstall();
  }

  /// Reads GitHub's latest release.
  Future<void> check() async {
    try {
      final json = await integrations.fetcher.getJson(
        'github',
        Uri.parse('https://api.github.com/repos/$kReleaseRepo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      );
      final tag = json is Map<String, Object?> ? json['tag_name'] : null;
      latest = tag is String ? AppVersion.tryParse(tag) : null;
      checkedAtMs = DateTime.now().millisecondsSinceEpoch;
      error = null;
    } on Object catch (e) {
      error = 'Couldn’t reach GitHub to check for updates.';
      _log.info('update check failed: $e');
    }
  }

  Future<String> mode() async => switch ((await integrations.setting(SettingKeys.hubUpdates))['mode']) {
        HubUpdateMode.nightly => HubUpdateMode.nightly,
        HubUpdateMode.auto => HubUpdateMode.auto,
        _ => HubUpdateMode.manual,
      };

  Future<void> _maybeInstall() async {
    final next = latest;
    if (!available || next == null || version == null || installing || !config.canSelfUpdate || _failed.contains(next)) return;
    switch (await mode()) {
      case HubUpdateMode.auto:
        await install();
      case HubUpdateMode.nightly:
        final db = integrations.kernel.db;
        final tz = (await db.select(db.households).getSingleOrNull())?.timezone ?? 'UTC';
        final time = HouseholdTime.named(tz);
        final minute = time.minuteOfDay(time.nowMs());
        if (minute >= 3 * 60 && minute < 5 * 60) await install();
    }
  }

  /// Asks the updater to replace this Hub with the newest image. Throws a
  /// [StateError] with a reason the family can read when it can't.
  Future<void> install() async {
    final next = latest;
    if (!config.canSelfUpdate) throw StateError('This Hub has no updater beside it (see compose.yml).');
    if (next == null || !available) throw StateError('There is no newer release.');
    if (installing) return;
    installing = true;
    error = null;
    await _save(attempt: next);
    try {
      final res = await integrations.fetcher.send(
        'updater',
        'POST',
        Uri.parse('${config.updaterUrl}/v1/update?async=true'),
        headers: {'Authorization': 'Bearer ${config.updaterToken}'},
        retry: false,
      );
      if (res.statusCode >= 300) throw HttpException('the updater answered ${res.statusCode}');
    } on Object catch (e) {
      await _failedToInstall(next, 'the updater didn’t take it ($e)');
      throw StateError('The updater didn’t take it.');
    }
    _log.info('asked the updater for $next');
    // Still answering after the grace period: nothing replaced this Hub.
    _watchdog?.cancel();
    _watchdog = Timer(installGrace, () => unawaited(_failedToInstall(next, 'the updater found no newer image to run')));
  }

  Future<void> _failedToInstall(AppVersion v, String why) async {
    _log.warning('$v didn’t install: $why');
    installing = false;
    _failed.add(v);
    error = '$v didn’t install: $why.';
    await _save();
  }

  File get _record => File(p.join(config.dataDir, 'update.json'));

  Future<void> _save({AppVersion? attempt}) async {
    try {
      await _record.writeAsString(jsonEncode({'attempt': ?attempt?.toString(), 'failed': [for (final v in _failed) '$v']}));
    } on Object catch (e) {
      _log.warning('could not save the update record: $e');
    }
  }

  /// After a restart: the release an install was asked for is running now,
  /// or that install didn't take.
  void _restore() {
    final Map<String, Object?> saved;
    try {
      if (!_record.existsSync()) return;
      saved = jsonDecode(_record.readAsStringSync()) as Map<String, Object?>;
    } on Object {
      return;
    }
    _failed.addAll([for (final v in (saved['failed'] as List<Object?>?) ?? const []) ?AppVersion.tryParse('$v')]);
    final attempt = AppVersion.tryParse('${saved['attempt'] ?? ''}');
    if (attempt == null) return;
    if (version != null && version! >= attempt) {
      _log.info('updated to $version');
    } else {
      _failed.add(attempt);
      error = '$attempt didn’t install: the Hub restarted on $versionName.';
    }
    unawaited(_save());
  }

  /// For Settings → Updates.
  Future<Map<String, Object?>> status() async => {
        'version': versionName,
        'latest': latest?.toString(),
        'available': available,
        'canInstall': config.canSelfUpdate,
        'mode': await mode(),
        'checkedAtMs': checkedAtMs,
        'installing': installing,
        'error': error,
      };

  void dispose() => _watchdog?.cancel();
}
