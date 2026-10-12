import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('storage');

/// Opens the Hub database (SPEC §8.1). SQLite with WAL by default; Postgres
/// via `DEARTH_DB_URL` is planned (drift_postgres; see PROGRESS.md).
DearthDb openHubDatabase({String? path, bool inMemory = false}) {
  if (inMemory) return DearthDb(NativeDatabase.memory());
  final file = File(path!);
  file.parent.createSync(recursive: true);
  return DearthDb(NativeDatabase.createInBackground(
    file,
    setup: (db) {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = NORMAL');
      db.execute('PRAGMA busy_timeout = 5000');
    },
  ));
}

/// Consistent online backup (`VACUUM INTO`), keeping the newest [keep].
Future<File?> backupDatabase(DearthDb db, String backupDir, {int keep = 14, String reason = 'nightly'}) async {
  Directory(backupDir).createSync(recursive: true);
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
  final out = File(p.join(backupDir, 'dearth-$reason-$stamp.db'));
  try {
    await db.customStatement('VACUUM INTO ?', [out.path]);
  } on Object catch (e) {
    _log.warning('Backup failed: $e');
    return null;
  }
  final files = Directory(backupDir).listSync().whereType<File>().where((f) => p.basename(f.path).startsWith('dearth-$reason-')).toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  for (final old in files.skip(keep)) {
    old.deleteSync();
  }
  return out;
}

/// AES-256-GCM vault for integration secrets (SPEC §9.5). Values are stored
/// in the `secrets` table and never synced to devices.
///
/// The key: the generated `secret.key` (256 random bits) is used as its
/// SHA-256. A key someone chose (`DEARTH_SECRET_KEY`) may be guessable, and
/// backups are plain copies of the database, so it's stretched with a salted
/// PBKDF2 (the admin password's 120k iterations) and those seals carry a
/// `v2:` prefix. Older seals still open and are re-sealed when read.
class SecretVault {
  SecretVault(this.db, String masterKey)
      : _master = masterKey,
        _chosen = !_generated.hasMatch(masterKey.trim()),
        _plainKey = Sha256().hash(utf8.encode(masterKey)).then((h) => SecretKey(h.bytes));

  final DearthDb db;
  final String _master;
  final bool _chosen;
  final Future<SecretKey> _plainKey;
  Future<SecretKey>? _stretched;
  final _algo = AesGcm.with256bits();

  static final _generated = RegExp(r'^[0-9a-fA-F]{64,}$');
  static const _v2 = 'v2:';

  Future<SecretKey> _stretchedKey() => _stretched ??= () async {
        var salt = await db.kvGet('vault.salt');
        if (salt == null) {
          final r = Random.secure();
          salt = base64.encode([for (var i = 0; i < 16; i++) r.nextInt(256)]);
          await db.kvSet('vault.salt', salt);
        }
        return Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 120000, bits: 256).deriveKeyFromPassword(password: _master, nonce: base64.decode(salt));
      }();

  Future<String> _encrypt(String plain) async {
    final box = await _algo.encrypt(utf8.encode(plain), secretKey: _chosen ? await _stretchedKey() : await _plainKey);
    final sealed = base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
    return _chosen ? '$_v2$sealed' : sealed;
  }

  Future<String> _decrypt(String sealed) async {
    final v2 = sealed.startsWith(_v2);
    final bytes = base64.decode(v2 ? sealed.substring(_v2.length) : sealed);
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final cipher = bytes.sublist(12, bytes.length - 16);
    final clear = await _algo.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: v2 ? await _stretchedKey() : await _plainKey);
    return utf8.decode(clear);
  }

  Future<void> put(String id, String value) async {
    await db.into(db.secrets).insertOnConflictUpdate(
          SecretEntry(id: id, value: await _encrypt(value), updatedMs: DateTime.now().millisecondsSinceEpoch),
        );
  }

  Future<String?> get(String id) async {
    final row = await (db.select(db.secrets)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    try {
      final value = await _decrypt(row.value);
      // Sealed before chosen keys were stretched: seal it again.
      if (_chosen && !row.value.startsWith(_v2)) await put(id, value);
      return value;
    } on SecretBoxAuthenticationError {
      _log.severe('Secret "$id" could not be decrypted (wrong DEARTH_SECRET_KEY?)');
      return null;
    }
  }

  Future<Map<String, Object?>?> getJson(String id) async {
    final v = await get(id);
    if (v == null) return null;
    final d = jsonDecode(v);
    return d is Map<String, Object?> ? d : null;
  }

  Future<void> putJson(String id, Map<String, Object?> value) => put(id, jsonEncode(value));

  Future<void> remove(String id) => (db.delete(db.secrets)..where((t) => t.id.equals(id))).go();

  Future<List<String>> ids({String prefix = ''}) async =>
      [for (final r in await db.select(db.secrets).get()) if (r.id.startsWith(prefix)) r.id];
}

/// Small typed accessors for `job_states` (cursors, sync tokens, health).
class JobStore {
  JobStore(this.db);
  final DearthDb db;

  Future<JobState?> read(String id) => (db.select(db.jobStates)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Map<String, Object?>> data(String id) async => decodeJsonMap((await read(id))?.data);

  Future<void> write(String id, {Map<String, Object?>? data, int? lastRunMs, int? lastOkMs, String? lastError, bool clearError = false}) async {
    final current = await read(id);
    await db.into(db.jobStates).insertOnConflictUpdate(JobStatesCompanion(
          id: Value(id),
          data: Value(data == null ? (current?.data ?? '{}') : jsonEncode(data)),
          lastRunMs: Value(lastRunMs ?? current?.lastRunMs),
          lastOkMs: Value(lastOkMs ?? current?.lastOkMs),
          lastError: Value(clearError ? null : (lastError ?? current?.lastError)),
        ));
  }
}
