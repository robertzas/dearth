import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Profile PIN hashing for grown-up mode (SPEC §9.1).
///
/// PBKDF2-HMAC-SHA256 instead of the spec's Argon2id: it is available in pure
/// Dart on every platform (including web, where shared displays verify PINs
/// offline). Iterations are sized so one verification stays well under the
/// 300 ms budget on the T1 frame. Format: `pbkdf2$<iterations>$<salt>$<hash>`
/// (base64url, no padding).
const int kPinIterations = 6000;

String hashPin(String pin, {int iterations = kPinIterations, Random? random}) {
  final r = random ?? Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
  final hash = pbkdf2Sha256(utf8.encode(pin), salt, iterations);
  return 'pbkdf2\$$iterations\$${_b64(salt)}\$${_b64(hash)}';
}

/// Constant-time verification of [pin] against a [hashPin] string.
bool verifyPin(String pin, String? stored) {
  if (stored == null) return false;
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1 || iterations > 1000000) return false;
  final List<int> salt;
  final List<int> expected;
  try {
    salt = base64Url.decode(base64Url.normalize(parts[2]));
    expected = base64Url.decode(base64Url.normalize(parts[3]));
  } on FormatException {
    return false;
  }
  final actual = pbkdf2Sha256(utf8.encode(pin), salt, iterations);
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}

/// PBKDF2 (RFC 8018) with HMAC-SHA256, one 32-byte block.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
