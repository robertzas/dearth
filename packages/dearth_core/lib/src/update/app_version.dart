import 'package:meta/meta.dart';

/// Where releases come from: every green push to main publishes one
/// (`.github/workflows/build.yml`), tagged `v<major>.<minor>.<run number>`,
/// with the Android APKs and the Hub image (SPEC §15.3).
const String kReleaseRepo = 'robertzas/dearth';

/// The household's choice of when the Hub installs a new release
/// (Settings → Updates): `{mode: manual | nightly | auto}`.
abstract final class HubUpdateMode {
  /// Only when a grown-up taps Install (the default).
  static const manual = 'manual';

  /// 3–5 am household time.
  static const nightly = 'nightly';

  /// As soon as the Hub sees it.
  static const auto = 'auto';
}

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
