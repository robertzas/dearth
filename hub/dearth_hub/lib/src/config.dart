import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:path/path.dart' as p;

/// Hub configuration from environment variables (SPEC §14.5).
class HubConfig {
  HubConfig({
    required this.dataDir,
    required this.secretKey,
    this.dbUrl,
    this.publicUrl,
    this.lanUrls = const [],
    this.port = 8080,
    this.host = '0.0.0.0',
    this.fakeProviders = false,
    this.webDir,
    this.adminPassword,
    this.photoDirs = const [],
    this.musicDirs = const [],
    this.logLevel = 'info',
    this.autoApprove = false,
    this.contact = 'dearth-hub',
    this.jobsEnabled = true,
    this.useVips = true,
  });

  /// Reads `DEARTH_*` variables. A missing secret key is generated once and
  /// kept in `<data>/secret.key` (with a warning to set it explicitly).
  static HubConfig fromEnvironment(Map<String, String> env, {void Function(String)? warn}) {
    String? get(String k) {
      final v = env[k]?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    List<String> list(String k) => (get(k) ?? '').split(RegExp('[:,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    bool flag(String k) => const {'1', 'true', 'yes', 'on'}.contains(get(k)?.toLowerCase());

    final dataDir = get('DEARTH_DATA_DIR') ?? p.join(Directory.current.path, 'data');
    Directory(dataDir).createSync(recursive: true);

    var secret = get('DEARTH_SECRET_KEY');
    final secretFile = get('DEARTH_SECRET_KEY_FILE');
    if (secret == null && secretFile != null) secret = File(secretFile).readAsStringSync().trim();
    if (secret == null) {
      final f = File(p.join(dataDir, 'secret.key'));
      if (f.existsSync()) {
        secret = f.readAsStringSync().trim();
      } else {
        secret = randomToken();
        f.writeAsStringSync(secret);
        if (!Platform.isWindows) Process.runSync('chmod', ['600', f.path]);
        warn?.call('DEARTH_SECRET_KEY not set; generated ${f.path}. Back it up: encrypted integration secrets need it.');
      }
    }

    return HubConfig(
      dataDir: dataDir,
      secretKey: secret,
      dbUrl: get('DEARTH_DB_URL'),
      publicUrl: get('DEARTH_PUBLIC_URL')?.replaceFirst(RegExp(r'/+$'), ''),
      lanUrls: list('DEARTH_LAN_URLS'),
      port: int.tryParse(get('DEARTH_PORT') ?? '') ?? 8080,
      host: get('DEARTH_HOST') ?? '0.0.0.0',
      fakeProviders: flag('DEARTH_FAKE_PROVIDERS'),
      webDir: get('DEARTH_WEB_DIR') ?? _bundledWebDir(),
      adminPassword: get('DEARTH_ADMIN_PASSWORD'),
      photoDirs: list('DEARTH_PHOTO_DIRS'),
      musicDirs: list('DEARTH_MUSIC_DIRS'),
      logLevel: get('DEARTH_LOG_LEVEL') ?? 'info',
      autoApprove: flag('DEARTH_AUTO_APPROVE'),
      contact: get('DEARTH_CONTACT') ?? 'dearth-hub',
      jobsEnabled: !flag('DEARTH_DISABLE_JOBS'),
    );
  }

  /// The web app shipped next to the binary in release archives
  /// (`bundle/bin/dearth_hub` + `bundle/web/`).
  static String? _bundledWebDir() {
    try {
      final dir = p.join(p.dirname(Platform.resolvedExecutable), '..', 'web');
      return File(p.join(dir, 'index.html')).existsSync() ? p.normalize(dir) : null;
    } on Object {
      return null;
    }
  }

  final String dataDir;
  final String secretKey;
  final String? dbUrl;

  /// Public HTTPS origin (OAuth redirects, webhooks, PWA).
  final String? publicUrl;
  final List<String> lanUrls;
  final int port;
  final String host;

  /// Deterministic providers for demos and E2E (no network).
  final bool fakeProviders;
  final String? webDir;
  final String? adminPassword;
  final List<String> photoDirs;
  final List<String> musicDirs;
  final String logLevel;

  /// Auto-approve every pairing request (development / E2E only).
  final bool autoApprove;
  final String contact;
  final bool jobsEnabled;

  /// Resize and blur images with libvips when it is installed. The Hub
  /// built into the app (SPEC §7.2 Solo mode) turns this off: phones and
  /// frames have no `vips`, and iOS can't start processes at all.
  final bool useVips;

  String get blobDir => p.join(dataDir, 'blobs');
  String get backupDir => p.join(dataDir, 'backups');
  String get dbPath => p.join(dataDir, 'dearth.db');
  bool get hasHttpsPublicUrl => publicUrl?.startsWith('https://') ?? false;
}
