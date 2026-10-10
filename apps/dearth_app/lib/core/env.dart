import 'package:flutter/foundation.dart';

/// Runtime flags from `--dart-define`s and (on web) the page URL.
///
/// * `?e2e=1` / `DEARTH_E2E=true` — force the semantics tree on so the
///   Playwright suite can select `flt-semantics-identifier`s (SPEC §16.3),
///   and disable ambient motion for stable screenshots.
/// * `?now=2026-10-02T19:42` / `DEARTH_NOW` — run the UI clock from a fixed
///   start instant (time still advances), for deterministic tests and demos.
/// * `?demo=1` / `DEARTH_DEMO=true` — start straight in demo mode.
/// * `?hub=http://…` / `DEARTH_HUB` — preset Hub URL for onboarding.
/// * `?reset=1` — wipe local data on start (E2E isolation).
/// * `?faces=1` — the demo family gets face photos (E2E: Who's That? shows
///   only with faces; without a Hub they draw as the person's emoji).
@immutable
class AppEnv {
  const AppEnv({
    this.e2e = false,
    this.fakeNow,
    this.forceDemo = false,
    this.hubUrl,
    this.reset = false,
    this.demoFaces = false,
    this.role,
    this.appVersion = 'dev',
  });

  factory AppEnv.fromPlatform() {
    final q = kIsWeb ? Uri.base.queryParameters : const <String, String>{};
    bool flag(String key, bool define) => define || const {'1', 'true', 'yes'}.contains(q[key]?.toLowerCase());
    String? str(String key, String define) => (q[key]?.isNotEmpty ?? false) ? q[key] : (define.isEmpty ? null : define);
    final nowRaw = str('now', const String.fromEnvironment('DEARTH_NOW'));
    return AppEnv(
      e2e: flag('e2e', const bool.fromEnvironment('DEARTH_E2E')),
      fakeNow: nowRaw == null ? null : DateTime.tryParse(nowRaw),
      forceDemo: flag('demo', const bool.fromEnvironment('DEARTH_DEMO')),
      hubUrl: str('hub', const String.fromEnvironment('DEARTH_HUB')),
      reset: flag('reset', false),
      demoFaces: flag('faces', false),
      role: str('role', const String.fromEnvironment('DEARTH_ROLE')),
      appVersion: const String.fromEnvironment('DEARTH_VERSION', defaultValue: '0.1.0-dev'),
    );
  }

  final bool e2e;

  /// Local wall-clock start instant for the UI clock (no zone → local).
  final DateTime? fakeNow;
  final bool forceDemo;
  final String? hubUrl;
  final bool reset;
  final bool demoFaces;

  /// Device role override for demo mode (`kitchen`, `personal`…).
  final String? role;
  final String appVersion;

  /// The origin this web app was served from (the Hub, normally).
  static String? get webOrigin => kIsWeb ? Uri.base.origin : null;

  static String get platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static bool get isDesktop =>
      !kIsWeb && const {TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.windows}.contains(defaultTargetPlatform);

  static bool get isMobileNative =>
      !kIsWeb && const {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);
}

/// The UI clock: real time, optionally shifted to start at [AppEnv.fakeNow].
/// HLC stamping always uses real time (sync correctness); only rendering and
/// "today" decisions use this clock.
class AppClock {
  AppClock({DateTime? startAt}) : _offset = startAt == null ? Duration.zero : startAt.difference(DateTime.now());

  final Duration _offset;

  DateTime now() => DateTime.now().add(_offset);
  int nowMs() => now().millisecondsSinceEpoch;
  bool get isShifted => _offset != Duration.zero;
}
