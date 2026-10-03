import 'dart:convert';
import 'dart:io';

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
class SecretVault {
  SecretVault(this.db, String masterKey) : _keyFuture = Sha256().hash(utf8.encode(masterKey)).then((h) => SecretKey(h.bytes));

  final DearthDb db;
  final Future<SecretKey> _keyFuture;
  final _algo = AesGcm.with256bits();

  Future<String> _encrypt(String plain) async {
    final box = await _algo.encrypt(utf8.encode(plain), secretKey: await _keyFuture);
    return base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String> _decrypt(String sealed) async {
    final bytes = base64.decode(sealed);
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final cipher = bytes.sublist(12, bytes.length - 16);
    final clear = await _algo.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: await _keyFuture);
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
      return await _decrypt(row.value);
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
