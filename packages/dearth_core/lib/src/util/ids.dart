import 'dart:math';

import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Namespace for deterministic (UUIDv5) ids. Never change it: every device
/// must derive the same id for the same natural key (SPEC §8.3).
const String kDearthIdNamespace = '6f3a0c8e-6a8f-5b2e-9d1c-4e2f7a9b0d11';

/// A new time-ordered random id (UUIDv7) for user-created rows.
String newId() => _uuid.v7();

/// A deterministic id for rows identified by a natural key, e.g.
/// `stableId('chore_instance', [choreId, date, profileId])`. Concurrent
/// creation on several devices converges on one row.
String stableId(String kind, List<Object?> parts) =>
    _uuid.v5(kDearthIdNamespace, '$kind|${parts.map((p) => p ?? '').join('|')}');

const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// A human-friendly code without ambiguous characters (no 0/O, 1/I).
String randomCode(int length, {Random? random}) {
  final r = random ?? Random.secure();
  return List.generate(length, (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)]).join();
}

/// A URL-safe random token with [bytes] bytes of entropy (hex encoded).
String randomToken({int bytes = 32, Random? random}) {
  final r = random ?? Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
