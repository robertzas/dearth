import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/display_state.dart';
import '../data/household.dart';
import '../providers.dart';
import 'app_release.dart';
import 'local_adb.dart';

export 'app_release.dart';

final _log = Logger('Updater');
const MethodChannel _channel = MethodChannel('app.dearth/update');

enum UpdatePhase {
  /// Not Android, or an embedder without Dearth's activity (widget tests).
  unsupported,
  idle,
  checking,
  upToDate,

  /// A newer release, not downloaded yet.
  available,
  downloading,

  /// Downloaded and checked against its published SHA-256.
  ready,
  installing,
}

const Object _keep = Object();

@immutable
class UpdateState {
  const UpdateState({this.phase = UpdatePhase.idle, this.current, this.latest, this.progress, this.error, this.checkedAtMs, this.silent = false});

  final UpdatePhase phase;

  /// This build's release version; null for a development build, which never
  /// installs updates by itself.
  final AppVersion? current;

  /// The newest release, when it's newer than this build.
  final AppRelease? latest;

  /// Download progress, 0…1.
  final double? progress;
  final String? error;
  final int? checkedAtMs;

  /// Installs without a prompt, through the device's own ADB ([LocalAdb]).
  final bool silent;

  UpdateState copyWith({UpdatePhase? phase, Object? latest = _keep, Object? progress = _keep, Object? error = _keep, int? checkedAtMs, bool? silent}) => UpdateState(
        phase: phase ?? this.phase,
        current: current,
        latest: identical(latest, _keep) ? this.latest : latest as AppRelease?,
        progress: identical(progress, _keep) ? this.progress : (progress as num?)?.toDouble(),
        error: identical(error, _keep) ? this.error : error as String?,
        checkedAtMs: checkedAtMs ?? this.checkedAtMs,
        silent: silent ?? this.silent,
      );
}

/// Keeps an Android install up to date with the newest GitHub release
/// (SPEC FR-ADM-04, §15.3). It looks two minutes after start and every four
/// hours, and Settings → Updates can ask now. A grown-up installs from
/// there; a display that can install silently (its own ADB, [LocalAdb]) can
/// also install by itself nightly or whenever it's idle ([mayAutoInstall]).
///
/// The app reads GitHub itself rather than through the Hub (the owner's
/// call, 2026-10-10): it works the same in demo, Solo and Hub modes, and a
/// display updates without waiting for a newer Hub.
///
/// Kept alive by the app root.
class AppUpdater extends Notifier<UpdateState> {
  static const _checkEvery = Duration(hours: 4);

  /// Long enough for pm to replace the app and `am start` to bring it back.
  static const _installGrace = Duration(minutes: 5);

  /// Where the silent install writes pm's answer, read back if it failed.
  static const _installLog = '/data/local/tmp/dearth-update.log';

  String? _abi;
  Timer? _tick;
  Timer? _watchdog;
  http.Client? _http;
  bool _busy = false;
  AppVersion? _verified;

  /// Builds that failed to install: never retried by themselves.
  final Set<AppVersion> _failed = {};

  @override
  UpdateState build() {
    final current = AppVersion.tryParse(ref.read(envProvider).appVersion);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return UpdateState(phase: UpdatePhase.unsupported, current: current);
    ref.onDispose(() {
      _tick?.cancel();
      _watchdog?.cancel();
      _http?.close();
    });
    ref.listen(displayProvider.select((d) => d.mode), (_, _) => unawaited(_maybeAutoInstall()));
    ref.listen(isNightTimeProvider, (_, _) => unawaited(_maybeAutoInstall()));
    ref.listen(deviceSettingsProvider.select((s) => s.updates), (_, _) => unawaited(_maybeAutoInstall()));
    Future.microtask(_start);
    return UpdateState(current: current);
  }

  http.Client get _client => _http ??= http.Client();

  Future<void> _start() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info');
      _abi = info?['abi'] as String?;
    } on MissingPluginException {
      _abi = null;
    } on PlatformException {
      _abi = null;
    }
    if (_abi == null) {
      state = state.copyWith(phase: UpdatePhase.unsupported);
      return;
    }
    await _settleLastAttempt();
    state = state.copyWith(silent: await _canInstallSilently());
    _tick = Timer(const Duration(minutes: 2), _onTick);
  }

  void _onTick() {
    unawaited(check());
    _tick = Timer(_checkEvery, _onTick);
  }

  /// Whether this device's adbd runs a shell for us without asking (a
  /// frame's ROM with open network ADB, as root or the shell user).
  Future<bool> _canInstallSilently() async {
    try {
      final id = (await LocalAdb().shell('id -u', timeout: const Duration(seconds: 5))).trim();
      return id == '0' || id == '2000';
    } on AdbException catch (e) {
      _log.fine('no silent installs: $e');
      return false;
    }
  }

  /// Asks GitHub for the latest release. On a display that installs by
  /// itself, a newer one downloads right away and installs when it may.
  Future<void> check() async {
    final abi = _abi;
    if (abi == null || _busy || state.phase == UpdatePhase.checking) return;
    final before = state.phase;
    state = state.copyWith(phase: UpdatePhase.checking, error: null);
    final AppRelease? release;
    try {
      final res = await _client
          .get(Uri.parse('https://api.github.com/repos/$kReleaseRepo/releases/latest'), headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
      release = AppRelease.fromGitHub(jsonDecode(res.body) as Map<String, Object?>, abi);
    } on Object catch (e) {
      _log.info('update check failed: $e');
      state = state.copyWith(phase: before == UpdatePhase.checking ? UpdatePhase.idle : before, error: 'Couldn’t reach GitHub to check for updates.');
      return;
    }
    final now = ref.read(appClockProvider).nowMs();
    final current = state.current;
    if (release == null || (current != null && !(release.version > current))) {
      state = state.copyWith(phase: UpdatePhase.upToDate, latest: null, checkedAtMs: now);
      return;
    }
    state = state.copyWith(phase: _verified == release.version ? UpdatePhase.ready : UpdatePhase.available, latest: release, checkedAtMs: now);
    if (_mayInstallByItself(release)) {
      try {
        await _download(release);
      } on Object catch (e) {
        state = state.copyWith(phase: UpdatePhase.available, progress: null, error: 'The download stopped: $e');
        return;
      }
      await _maybeAutoInstall();
    }
  }

  bool _mayInstallByItself(AppRelease r) =>
      state.silent && state.current != null && !_failed.contains(r.version) && ref.read(deviceSettingsProvider).updates != UpdateMode.manual;

  Future<void> _maybeAutoInstall() async {
    final r = state.latest;
    if (r == null || _busy || !_mayInstallByItself(r)) return;
    if (state.phase != UpdatePhase.available && state.phase != UpdatePhase.ready) return;
    if (!await _mayInstallNow()) return;
    await install(auto: true);
  }

  Future<bool> _mayInstallNow() async {
    final time = ref.read(householdTimeProvider);
    final now = time.nowMs();
    final db = ref.read(dbProvider);
    final timers = await (db.select(db.kitchenTimers)..where((t) => t.deleted.equals(false) & t.status.equals(TimerStatus.running))).get();
    final phases = {for (final t in timers) t.phase(now)};
    return mayAutoInstall(
      mode: ref.read(deviceSettingsProvider).updates,
      idle: ref.read(displayProvider).mode != DisplayMode.active,
      timerRunning: phases.contains(TimerPhase.running) || phases.contains(TimerPhase.ringing),
      nightTime: ref.read(nightWindowProvider) == null ? null : ref.read(isNightTimeProvider),
      minuteOfDay: time.minuteOfDay(now),
    );
  }

  /// Downloads [r]'s APK (once), checked against its published SHA-256.
  Future<File> _download(AppRelease r) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'dearth-${r.version}.apk'));
    if (_verified == r.version && file.existsSync()) return file;
    await for (final f in dir.list()) {
      if (f.path != file.path) await f.delete(recursive: true);
    }
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0.0, error: null);
    final res = await _client.send(http.Request('GET', r.apkUrl)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
    final total = res.contentLength ?? r.size;
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    final out = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        out.add(chunk);
        hash.add(chunk);
        got += chunk.length;
        // Whole percents: Settings rebuilds on each.
        if (total > 0 && (got * 100 ~/ total) != ((got - chunk.length) * 100 ~/ total)) state = state.copyWith(progress: got / total);
      }
    } finally {
      await out.close();
    }
    hash.close();
    if (r.sha256 != null && '${digest.value}' != r.sha256) {
      await file.delete();
      throw const FormatException('the APK doesn’t match its published checksum');
    }
    _verified = r.version;
    state = state.copyWith(phase: UpdatePhase.ready, progress: null);
    return file;
  }

  /// Downloads and installs the latest release: a grown-up's Install, or a
  /// display updating itself ([auto]), which checks again after the
  /// download that it still may. Silently, pm replaces the running app and
  /// `am start` brings the new one back; elsewhere Android asks first.
  Future<void> install({bool auto = false}) async {
    final r = state.latest;
    if (r == null || _busy) return;
    _busy = true;
    try {
      final File file;
      try {
        file = await _download(r);
      } on Object catch (e) {
        state = state.copyWith(phase: UpdatePhase.available, progress: null, error: 'The download stopped: $e');
        return;
      }
      if (auto && !await _mayInstallNow()) return;
      if (state.silent) {
        state = state.copyWith(phase: UpdatePhase.installing, error: null);
        await _saveAttempt(r.version);
        try {
          await LocalAdb().shell(silentInstallCommand(file.path, file.lengthSync()));
        } on AdbException catch (e) {
          await _failedToInstall(r.version, '$e');
          return;
        }
        // Still running after the grace period: pm didn't replace us.
        _watchdog?.cancel();
        _watchdog = Timer(_installGrace, () => unawaited(_settleLastAttempt()));
      } else {
        final answer = await _channel.invokeMethod<String>('install', file.path);
        state = state.copyWith(
          phase: UpdatePhase.ready,
          error: answer == 'permission' ? 'Allow Dearth to install apps in the screen Android just opened, then tap Install again.' : null,
        );
      }
    } on Object catch (e) {
      _log.warning('install failed', e);
      state = state.copyWith(phase: UpdatePhase.ready, error: 'The update didn’t install: $e');
    } finally {
      _busy = false;
    }
  }

  /// The shell command that installs [apk] and starts the new app. It runs
  /// on under nohup after adbd's shell returns, because pm stops this app
  /// (and so this connection) to replace it.
  static String silentInstallCommand(String apk, int size) =>
      "nohup sh -c 'cat $apk | pm install -r -S $size > $_installLog 2>&1; am start -n app.dearth/.MainActivity' > /dev/null 2>&1 &";

  Future<File> _attemptFile() async => File(p.join((await getApplicationSupportDirectory()).path, 'update.json'));

  /// Remembers the version an install started for ([version], null once
  /// it's settled) and the versions that failed.
  Future<void> _saveAttempt(AppVersion? version) async {
    try {
      await (await _attemptFile()).writeAsString(jsonEncode({'attempt': ?version?.toString(), 'failed': [for (final v in _failed) '$v']}));
    } on Object catch (e) {
      _log.warning('could not save the update attempt', e);
    }
  }

  /// After a start (or the install grace period): the version an install was
  /// started for is running now, or that install failed. A failed version is
  /// remembered, so the display doesn't try it again by itself.
  Future<void> _settleLastAttempt() async {
    final Map<String, Object?> saved;
    try {
      final f = await _attemptFile();
      if (!f.existsSync()) return;
      saved = jsonDecode(await f.readAsString()) as Map<String, Object?>;
    } on Object {
      return;
    }
    _failed.addAll([for (final v in (saved['failed'] as List<Object?>?) ?? const []) ?AppVersion.tryParse('$v')]);
    final attempt = AppVersion.tryParse('${saved['attempt'] ?? ''}');
    if (attempt == null) return;
    final current = state.current;
    if (current != null && current >= attempt) {
      _log.info('updated to $current');
      await _saveAttempt(null);
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
      if (dir.existsSync()) await dir.delete(recursive: true);
      return;
    }
    var why = 'Android didn’t install it.';
    try {
      final log = (await LocalAdb().shell('cat $_installLog', timeout: const Duration(seconds: 5))).trim();
      if (log.isNotEmpty) why = log.split('\n').last;
    } on AdbException {
      // The reason stays unknown.
    }
    await _failedToInstall(attempt, why);
  }

  Future<void> _failedToInstall(AppVersion version, String why) async {
    _log.warning('$version failed to install: $why');
    _failed.add(version);
    await _saveAttempt(null);
    state = state.copyWith(phase: state.latest == null ? UpdatePhase.idle : UpdatePhase.ready, error: '$version didn’t install: $why');
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

final appUpdaterProvider = NotifierProvider<AppUpdater, UpdateState>(AppUpdater.new);
