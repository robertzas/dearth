import 'package:flutter/foundation.dart';

/// Where releases come from: every green push to main publishes one
/// (`.github/workflows/build.yml`), tagged `v<major>.<minor>.<run number>`.
const String kReleaseRepo = 'robertzas/dearth';

/// A release's semantic version. CI makes the patch the run number, so a
/// later push is always a higher version (`.github/actions/version`).
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// A release version (`0.1.97`, a tag's `v0.1.97`), or null for a build
  /// made anywhere else (`0.1.0-dev`, `0.1.0-local.abc123` from
  /// `deploy_frame.sh --build`): those never update by themselves, so a
  /// developer's build stays until someone replaces it. Releases from
  /// before semantic versions (`0.1.0-build.95`) read as `0.1.95`, so a
  /// display running one still sees the next release as newer.
  static AppVersion? tryParse(String version) {
    final v = version.trim().replaceFirst(RegExp('^v'), '');
    final legacy = RegExp(r'^(\d+)\.(\d+)\.\d+-build\.(\d+)$').firstMatch(v);
    final m = legacy ?? RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(v);
    return m == null ? null : AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  @override
  int compareTo(AppVersion other) => major != other.major ? major - other.major : (minor != other.minor ? minor - other.minor : patch - other.patch);

  bool operator >(AppVersion other) => compareTo(other) > 0;

  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// A published release's APK for one ABI.
@immutable
class AppRelease {
  const AppRelease({required this.tag, required this.version, required this.apkUrl, required this.size, this.sha256, this.publishedAt});

  /// `v0.1.97`.
  final String tag;
  final AppVersion version;
  final Uri apkUrl;
  final int size;

  /// The asset's SHA-256 as GitHub reports it (hex), when it does.
  final String? sha256;
  final DateTime? publishedAt;

  /// The release in GitHub's `releases/latest` answer, with the APK built
  /// for [abi] (`dearth-<version>-android-<abi>.apk`), or null when it has
  /// none or isn't a release version.
  static AppRelease? fromGitHub(Map<String, Object?> json, String abi) {
    final tag = json['tag_name'];
    if (tag is! String || json['draft'] == true) return null;
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;
    final assets = json['assets'] is List<Object?> ? json['assets']! as List<Object?> : const <Object?>[];
    for (final a in assets.whereType<Map<String, Object?>>()) {
      final name = a['name'];
      final url = a['browser_download_url'];
      if (name is! String || url is! String || !name.endsWith('-android-$abi.apk')) continue;
      final digest = a['digest'];
      return AppRelease(
        tag: tag,
        version: version,
        apkUrl: Uri.parse(url),
        size: (a['size'] as num?)?.toInt() ?? 0,
        sha256: digest is String && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
        publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is AppRelease && other.tag == tag && other.apkUrl == apkUrl && other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(tag, apkUrl, sha256);
}

/// When a display installs a new release by itself (SPEC §15.3).
abstract final class UpdateMode {
  /// Only when a grown-up taps Install (the default).
  static const manual = 'manual';

  /// During the night hours, while the night clock or the photo frame is up.
  static const nightly = 'nightly';

  /// As soon as nobody is using it: the photo frame, the night clock, or
  /// the screen off.
  static const idle = 'idle';
}

/// Whether an automatic install may start now. Never while someone uses
/// the display ([idle] is false) or a kitchen timer counts down: the app
/// restarts to update, and a timer's alarm must not be lost. Nightly waits
/// for the household's night hours ([nightTime]); with no night schedule,
/// 2–5 am household time ([minuteOfDay]).
bool mayAutoInstall({required String mode, required bool idle, required bool timerRunning, required bool? nightTime, required int minuteOfDay}) {
  if (!idle || timerRunning) return false;
  return switch (mode) {
    UpdateMode.idle => true,
    UpdateMode.nightly => nightTime ?? (minuteOfDay >= 2 * 60 && minuteOfDay < 5 * 60),
    _ => false,
  };
}
