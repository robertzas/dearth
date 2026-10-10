import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import 'config.dart';
import 'kernel.dart';
import 'storage.dart';

final _log = Logger('auth');

String hashToken(String token) => crypto.sha256.convert(utf8.encode(token)).toString();

/// Pairing status as returned to a waiting device.
class PairStatus {
  const PairStatus(this.status, {this.token, this.deviceId, this.role, this.admin = false, this.name});
  final String status;
  final String? token;
  final String? deviceId;
  final String? role;
  final bool admin;

  /// The device's name on the Hub (a rejoining display keeps its own).
  final String? name;

  Map<String, Object?> toJson() => {
        'status': status,
        'token': ?token,
        'deviceId': ?deviceId,
        'role': ?role,
        'admin': admin,
        'name': ?name,
      };
}

/// Device tokens, the admin password and pairing (SPEC §9.2, §9.4).
class HubAuth {
  HubAuth(this.kernel, this.config, this.vault);

  final HubKernel kernel;
  final HubConfig config;
  final SecretVault vault;
  DearthDb get db => kernel.db;

  static const _adminSecret = 'admin:password';
  static const pairingTtl = Duration(minutes: 15);
  static const enrollTtl = Duration(minutes: 30);

  // ─────────────────────────────── Admin ───────────────────────────────────

  /// Ensures an admin password exists. Returns a newly generated one (to be
  /// printed once) or null.
  Future<String?> ensureAdminPassword() async {
    if (config.adminPassword != null) {
      await vault.put(_adminSecret, await _hashPassword(config.adminPassword!));
      return null;
    }
    if (await vault.get(_adminSecret) != null) return null;
    final generated = randomCode(12);
    await vault.put(_adminSecret, await _hashPassword(generated));
    return generated;
  }

  Future<bool> checkAdminPassword(String password) async {
    final stored = await vault.get(_adminSecret);
    if (stored == null) return false;
    final parts = stored.split(r'$');
    if (parts.length != 4) return false;
    final iterations = int.parse(parts[1]);
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final actual = await _pbkdf2(password, salt, iterations);
    return _constantTimeEquals(actual, expected);
  }

  Future<String> _hashPassword(String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    const iterations = 120000;
    final hash = await _pbkdf2(password, salt, iterations);
    return 'pbkdf2\$$iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
  }

  Future<List<int>> _pbkdf2(String password, List<int> salt, int iterations) async {
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return key.extractBytes();
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ─────────────────────────────── Devices ─────────────────────────────────

  Future<DeviceIdentity?> deviceForToken(String? token) async {
    if (token == null || token.isEmpty) return null;
    final row = await (db.select(db.deviceAuths)..where((t) => t.tokenHash.equals(hashToken(token)))).getSingleOrNull();
    if (row == null || row.revokedMs != null) return null;
    return DeviceIdentity(deviceId: row.deviceId, role: row.role, admin: row.admin, name: row.name);
  }

  Future<void> touch(String deviceId) => (db.update(db.deviceAuths)..where((t) => t.deviceId.equals(deviceId)))
      .write(DeviceAuthsCompanion(lastSeenMs: Value(DateTime.now().millisecondsSinceEpoch)));

  Future<void> revoke(String deviceId) async {
    await (db.update(db.deviceAuths)..where((t) => t.deviceId.equals(deviceId)))
        .write(DeviceAuthsCompanion(revokedMs: Value(DateTime.now().millisecondsSinceEpoch)));
    await kernel.delete('devices', deviceId);
  }

  /// Updates role/admin for an existing device token.
  Future<void> setDeviceRole(String deviceId, {String? role, bool? admin}) async {
    await (db.update(db.deviceAuths)..where((t) => t.deviceId.equals(deviceId))).write(DeviceAuthsCompanion(
          role: role == null ? const Value.absent() : Value(role),
          admin: admin == null ? const Value.absent() : Value(admin),
        ));
    if (role != null) await kernel.upsert('devices', deviceId, {'role': role});
  }

  Future<List<DeviceAuth>> devices() => (db.select(db.deviceAuths)..where((t) => t.revokedMs.isNull())).get();

  Future<DeviceAuth?> device(String deviceId) => (db.select(db.deviceAuths)..where((t) => t.deviceId.equals(deviceId))).getSingleOrNull();

  // ─────────────────────────────── Pairing ─────────────────────────────────

  /// A device asks to pair. Returns (pairingId, code, secret).
  Future<(String, String, String)> startPairing({required String name, String? platform, String? model, String? role}) async {
    final id = newId();
    final code = randomCode(6);
    final secret = randomToken(bytes: 16);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.pairings).insert(PairingsCompanion.insert(
          id: id,
          code: code,
          secretHash: Value(hashToken(secret)),
          deviceName: Value(name.isEmpty ? 'Display' : name),
          platform: Value(platform),
          model: Value(model),
          role: Value(DeviceRole.all.contains(role) ? role! : DeviceRole.kitchen),
          status: Value(config.autoApprove ? 'approved' : 'pending'),
          admin: Value(config.autoApprove),
          requestedMs: now,
          expiresMs: now + pairingTtl.inMilliseconds,
        ));
    _log.info('Pairing requested by "$name" ($platform) — code $code${config.autoApprove ? ' (auto-approved)' : ''}');
    return (id, code, secret);
  }

  /// Admin approves a pending code.
  Future<bool> approve(String code, {String? role, bool? admin, String? name, String? orientation}) async {
    final p = await _pending(code);
    if (p == null) return false;
    await (db.update(db.pairings)..where((t) => t.id.equals(p.id))).write(PairingsCompanion(
          status: const Value('approved'),
          role: role == null ? const Value.absent() : Value(role),
          admin: admin == null ? const Value.absent() : Value(admin),
          deviceName: name == null ? const Value.absent() : Value(name),
          orientation: orientation == null ? const Value.absent() : Value(orientation),
        ));
    return true;
  }

  /// Pre-approved enrollment code for unattended provisioning (tool scripts).
  /// With [replaces], the code brings that device back under its own id (a
  /// display that was reset, `tool/perf_gate.sh`): the claim gives it a new
  /// token and keeps its row, settings and all.
  Future<String> enroll({required String name, String role = DeviceRole.kitchen, bool admin = false, String? orientation, String? replaces, Duration ttl = enrollTtl}) async {
    final code = randomCode(8);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.pairings).insert(PairingsCompanion.insert(
          id: newId(),
          code: code,
          deviceName: Value(name),
          role: Value(role),
          admin: Value(admin),
          orientation: Value(orientation),
          deviceId: Value(replaces),
          status: const Value('approved'),
          requestedMs: now,
          expiresMs: now + ttl.inMilliseconds,
        ));
    return code;
  }

  /// Device polls its pairing. Issues the token exactly once when approved.
  Future<PairStatus> pairingStatus(String pairingId, String secret) async {
    final p = await (db.select(db.pairings)..where((t) => t.id.equals(pairingId))).getSingleOrNull();
    if (p == null || p.secretHash != hashToken(secret)) return const PairStatus('unknown');
    return _resolve(p);
  }

  /// Device redeems an enrollment code (no polling secret involved).
  Future<PairStatus> claim(String code, {String? platform, String? model, String? name}) async {
    final p = await (db.select(db.pairings)..where((t) => t.code.equals(code.toUpperCase()) & t.secretHash.isNull())).getSingleOrNull();
    if (p == null) return const PairStatus('unknown');
    if (platform != null || model != null || name != null) {
      await (db.update(db.pairings)..where((t) => t.id.equals(p.id))).write(PairingsCompanion(
            platform: Value(platform ?? p.platform),
            model: Value(model ?? p.model),
            deviceName: Value(name ?? p.deviceName),
          ));
    }
    return _resolve((await (db.select(db.pairings)..where((t) => t.id.equals(p.id))).getSingle()));
  }

  Future<PairStatus> _resolve(Pairing p) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (p.status == 'claimed') return const PairStatus('claimed');
    if (p.expiresMs < now) return const PairStatus('expired');
    if (p.status != 'approved') return const PairStatus('pending');
    // An enrollment made for a device that's coming back (enroll's
    // replaces) carries its id; anything else is a new device.
    final returning = p.deviceId == null ? null : await device(p.deviceId!);
    // Removed from the Hub since the code was made: it stays removed.
    if (p.deviceId != null && (returning == null || returning.revokedMs != null)) return const PairStatus('expired');
    final deviceId = returning?.deviceId ?? newId();
    final token = randomToken();
    await db.transaction(() async {
      if (returning != null) {
        // The old token stops working: the device's only key is the new one.
        await (db.update(db.deviceAuths)..where((t) => t.deviceId.equals(deviceId))).write(DeviceAuthsCompanion(
              tokenHash: Value(hashToken(token)),
              name: Value(p.deviceName),
              role: Value(p.role),
              admin: Value(p.admin),
            ));
      } else {
        await db.into(db.deviceAuths).insert(DeviceAuthsCompanion.insert(
              deviceId: deviceId,
              tokenHash: hashToken(token),
              name: Value(p.deviceName),
              role: Value(p.role),
              admin: Value(p.admin),
              createdMs: now,
            ));
      }
      await (db.update(db.pairings)..where((t) => t.id.equals(p.id)))
          .write(PairingsCompanion(status: const Value('claimed'), deviceId: Value(deviceId)));
    });
    await kernel.upsert('devices', deviceId, {
      // A returning display keeps its row (orientation, size, its settings).
      if (returning == null) ...{'name': p.deviceName, 'role': p.role, 'orientation': p.orientation ?? 'auto'},
      'platform': p.platform,
      'model': p.model,
    });
    _log.info('Device "${p.deviceName}" ${returning == null ? 'paired' : 'rejoined'} as ${p.role}${p.admin ? ' (admin)' : ''}');
    return PairStatus('approved', token: token, deviceId: deviceId, role: p.role, admin: p.admin, name: p.deviceName);
  }

  Future<Pairing?> _pending(String code) async {
    final p = await (db.select(db.pairings)..where((t) => t.code.equals(code.toUpperCase()))).getSingleOrNull();
    if (p == null || p.status != 'pending' || p.expiresMs < DateTime.now().millisecondsSinceEpoch) return null;
    return p;
  }

  Future<List<Pairing>> pendingPairings() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (db.select(db.pairings)..where((t) => t.status.equals('pending') & t.expiresMs.isBiggerThanValue(now))).get();
  }
}
