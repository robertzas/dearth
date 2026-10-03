import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'env.dart';

/// How this device gets its data.
enum SessionMode {
  /// First run: onboarding decides.
  none,

  /// Paired with a Hub (SPEC §7.2 "Hub mode").
  hub,

  /// Local demo household; nothing leaves the device.
  demo,
}

@immutable
class Session {
  const Session({
    this.mode = SessionMode.none,
    this.hubUrl,
    this.deviceId,
    this.token,
    this.role = DeviceRole.kitchen,
    this.admin = false,
    this.deviceName,
  });

  final SessionMode mode;
  final String? hubUrl;
  final String? deviceId;
  final String? token;
  final String role;
  final bool admin;
  final String? deviceName;

  static const demoDeviceId = 'local-device';

  bool get isHub => mode == SessionMode.hub && hubUrl != null && token != null;
  bool get isDemo => mode == SessionMode.demo;
  bool get isReady => isHub || isDemo;

  /// The `devices` row describing this device.
  String get effectiveDeviceId => deviceId ?? demoDeviceId;

  Session copyWith({SessionMode? mode, String? role, bool? admin, String? deviceName}) => Session(
        mode: mode ?? this.mode,
        hubUrl: hubUrl,
        deviceId: deviceId,
        token: token,
        role: role ?? this.role,
        admin: admin ?? this.admin,
        deviceName: deviceName ?? this.deviceName,
      );

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.mode == mode &&
      other.hubUrl == hubUrl &&
      other.deviceId == deviceId &&
      other.token == token &&
      other.role == role &&
      other.admin == admin &&
      other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(mode, hubUrl, deviceId, token, role, admin, deviceName);
}

/// Persists the session. The device token lives in Keystore/Keychain-backed
/// storage on phones and tablets (SPEC §9.2); elsewhere it stays in the
/// app-private database (web over LAN http has no WebCrypto, and Linux
/// kiosks rarely run an unlocked keyring).
class SessionStore {
  SessionStore(this.db);
  final DearthDb db;

  static const _secure = FlutterSecureStorage();
  static const _tokenKey = 'dearth.device_token';

  bool get _useSecure => AppEnv.isMobileNative;

  Future<Session> load() async {
    final rawMode = await db.kvGet('session.mode');
    final mode = SessionMode.values.firstWhere((m) => m.name == rawMode, orElse: () => SessionMode.none);
    String? token;
    if (mode == SessionMode.hub) {
      token = _useSecure ? await _readSecure() : await db.kvGet('session.token');
    }
    return Session(
      mode: mode,
      hubUrl: await db.kvGet('session.hub'),
      deviceId: await db.kvGet('session.device'),
      token: token,
      role: await db.kvGet('session.role') ?? DeviceRole.kitchen,
      admin: await db.kvGet('session.admin') == 'true',
      deviceName: await db.kvGet('session.name'),
    );
  }

  Future<String?> _readSecure() async {
    try {
      return await _secure.read(key: _tokenKey);
    } on Object {
      return null;
    }
  }

  Future<void> save(Session s) async {
    Future<void> put(String k, String? v) => v == null ? db.kvDelete(k) : db.kvSet(k, v);
    await put('session.mode', s.mode.name);
    await put('session.hub', s.hubUrl);
    await put('session.device', s.deviceId);
    await put('session.role', s.role);
    await put('session.admin', '${s.admin}');
    await put('session.name', s.deviceName);
    if (_useSecure) {
      try {
        s.token == null ? await _secure.delete(key: _tokenKey) : await _secure.write(key: _tokenKey, value: s.token);
        await db.kvDelete('session.token');
        return;
      } on Object {
        // Fall through to the database when the keystore is unavailable.
      }
    }
    await put('session.token', s.token);
  }

  /// Wipes every local table (leaving a fresh replica) and the session.
  Future<void> wipe() async {
    await db.batch((b) {
      for (final t in db.allTables) {
        b.customStatement('DELETE FROM "${t.actualTableName}"');
      }
    });
    db.notifyUpdates({for (final t in db.allTables) TableUpdate.onTable(t)});
    if (_useSecure) {
      try {
        await _secure.delete(key: _tokenKey);
      } on Object {
        // ignore
      }
    }
  }
}
