import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('blobs');

/// Content-addressed blob store + libvips derivative pipeline (SPEC §14.4).
class BlobStore {
  BlobStore(this.db, this.dir) {
    Directory(p.join(dir, 'v')).createSync(recursive: true);
  }

  final DearthDb db;
  final String dir;
  bool? _vips;
  final Map<String, Future<File?>> _inflight = {};

  static const maxUploadBytes = 50 * 1024 * 1024;

  Future<bool> get vipsAvailable async => _vips ??= await _probeVips();

  static Future<bool> _probeVips() async {
    try {
      final r = await Process.run('vips', ['--version']);
      return r.exitCode == 0;
    } on ProcessException {
      _log.warning('libvips (vips) not found — photos are served without resizing');
      return false;
    }
  }

  File fileFor(String sha) => File(p.join(dir, sha.substring(0, 2), sha));

  Future<BlobEntry?> entry(String sha) => (db.select(db.blobs)..where((t) => t.sha.equals(sha))).getSingleOrNull();

  Future<BlobEntry?> byOrigin(String origin) =>
      (db.select(db.blobs)..where((t) => t.origin.equals(origin))..limit(1)).getSingleOrNull();

  /// Stores bytes (idempotent) and records metadata.
  /// Saves in progress, by sha: the same image saved twice at once (one
  /// photo twice in an album, fetched by two workers) is written once.
  final Map<String, Future<BlobEntry>> _saving = {};

  Future<BlobEntry> put(List<int> bytes, {required String mime, String? origin}) {
    final sha = crypto.sha256.convert(bytes).toString();
    return _saving[sha] ??= _put(sha, bytes, mime: mime, origin: origin).whenComplete(() {
      _saving.remove(sha);
    });
  }

  Future<BlobEntry> _put(String sha, List<int> bytes, {required String mime, String? origin}) async {
    final existing = await entry(sha);
    if (existing != null) return existing;
    final f = fileFor(sha);
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    int? w;
    int? h;
    if (mime.startsWith('image/') && await vipsAvailable) {
      (w, h) = await _dims(f.path);
    }
    final row = BlobEntry(
      sha: sha,
      mime: mime,
      bytes: bytes.length,
      width: w,
      height: h,
      origin: origin,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    await db.into(db.blobs).insertOnConflictUpdate(row);
    return row;
  }

  /// Stores an image normalized to at most [maxEdge] px (JPEG), keeping the
  /// original only when vips is unavailable. Used for photo sources so the
  /// store holds display-ready derivatives, not 12 MP originals.
  Future<BlobEntry> putImage(List<int> bytes, {String? origin, int maxEdge = 2048}) async {
    if (!await vipsAvailable) return put(bytes, mime: _sniffMime(bytes), origin: origin);
    final tmpDir = await Directory.systemTemp.createTemp('dearth-img');
    try {
      final input = File(p.join(tmpDir.path, 'in'));
      await input.writeAsBytes(bytes);
      final out = p.join(tmpDir.path, 'out.jpg');
      final r = await Process.run('vips', ['thumbnail', input.path, '$out[Q=85,strip]', '$maxEdge', '--size', 'down']);
      if (r.exitCode != 0) {
        _log.warning('vips failed on ${origin ?? 'upload'}: ${r.stderr}');
        return await put(bytes, mime: _sniffMime(bytes), origin: origin);
      }
      return await put(await File(out).readAsBytes(), mime: 'image/jpeg', origin: origin);
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }

  /// A cached derivative: fit inside (w,h) or cover-crop, optionally blurred
  /// (pre-blurred screensaver backgrounds, SPEC FR-SSV-04).
  Future<File?> variant(String sha, {int? width, int? height, bool cover = false, bool blur = false}) async {
    final original = fileFor(sha);
    if (!original.existsSync()) return null;
    if ((width == null && height == null && !blur) || !await vipsAvailable) return original;
    final w = (width ?? height ?? 640).clamp(16, 4096);
    final h = (height ?? width ?? 640).clamp(16, 4096);
    final key = '${sha}_${w}x${h}_${cover ? 'c' : 'i'}${blur ? '_b' : ''}.jpg';
    final out = File(p.join(dir, 'v', key));
    if (out.existsSync()) return out;
    return _inflight.putIfAbsent(key, () async {
      try {
        if (blur) {
          final small = '${out.path}.small.v';
          final a = await Process.run('vips', ['thumbnail', original.path, small, '96', '--height', '96', '--size', 'down']);
          if (a.exitCode != 0) return original;
          final b = await Process.run('vips', ['gaussblur', small, '${out.path}[Q=70,strip]', '4']);
          File(small).deleteSync();
          return b.exitCode == 0 ? out : original;
        }
        final args = ['thumbnail', original.path, '${out.path}[Q=82,strip]', '$w', '--height', '$h', '--size', 'down', if (cover) ...['--crop', 'attention']];
        final r = await Process.run('vips', args);
        if (r.exitCode != 0) {
          _log.warning('variant $key failed: ${r.stderr}');
          return original;
        }
        return out;
      } finally {
        unawaited(_inflight.remove(key));
      }
    });
  }

  Future<(int?, int?)> _dims(String path) async {
    try {
      final w = await Process.run('vipsheader', ['-f', 'width', path]);
      final h = await Process.run('vipsheader', ['-f', 'height', path]);
      return (int.tryParse('${w.stdout}'.trim()), int.tryParse('${h.stdout}'.trim()));
    } on ProcessException {
      return (null, null);
    }
  }

  /// Fetches a remote image through the Hub (cached forever by origin URL).
  Future<BlobEntry?> fetchRemoteImage(Fetcher fetcher, Uri url, {Map<String, String> headers = const {}, int maxEdge = 2048}) async {
    final key = url.toString();
    final cached = await byOrigin(key);
    if (cached != null && fileFor(cached.sha).existsSync()) return cached;
    final res = await fetcher.send('image', 'GET', url, headers: {'Accept': 'image/*', ...headers});
    if (res.bodyBytes.length > maxUploadBytes) throw ProviderException('image', 'Image too large');
    final type = res.headers['content-type'] ?? _sniffMime(res.bodyBytes);
    if (!type.startsWith('image/')) throw ProviderException('image', 'Not an image ($type)');
    return putImage(res.bodyBytes, origin: key, maxEdge: maxEdge);
  }

  /// Deletes blobs (and variants) no row references and older than [minAge].
  Future<int> garbageCollect(Set<String> referenced, {Duration minAge = const Duration(days: 7)}) async {
    final cutoff = DateTime.now().subtract(minAge).millisecondsSinceEpoch;
    var removed = 0;
    for (final b in await db.select(db.blobs).get()) {
      if (referenced.contains(b.sha) || b.createdMs > cutoff || b.origin != null) continue;
      final f = fileFor(b.sha);
      if (f.existsSync()) f.deleteSync();
      for (final v in Directory(p.join(dir, 'v')).listSync().whereType<File>()) {
        if (p.basename(v.path).startsWith(b.sha)) v.deleteSync();
      }
      await (db.delete(db.blobs)..where((t) => t.sha.equals(b.sha))).go();
      removed++;
    }
    return removed;
  }

  static String _sniffMime(List<int> b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'image/webp';
    if (b.length > 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') return 'image/heic';
    if (b.length > 3 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return 'audio/mpeg';
    return 'application/octet-stream';
  }

  static String mimeForPath(String path) => switch (p.extension(path).toLowerCase()) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.heic' || '.heif' => 'image/heic',
        '.gif' => 'image/gif',
        '.mp3' => 'audio/mpeg',
        '.m4a' || '.aac' => 'audio/mp4',
        '.ogg' || '.opus' => 'audio/ogg',
        '.flac' => 'audio/flac',
        '.wav' => 'audio/wav',
        _ => 'application/octet-stream',
      };
}
