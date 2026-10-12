import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/src/storage.dart';
import 'package:test/test.dart';

/// A seal as the vault made them before chosen keys were stretched.
Future<String> legacySeal(String key, String plain) async {
  final k = SecretKey((await Sha256().hash(utf8.encode(key))).bytes);
  final box = await AesGcm.with256bits().encrypt(utf8.encode(plain), secretKey: k);
  return base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
}

/// Integration secrets at rest (SUGGESTIONS Hub §7).
void main() {
  test('the generated key seals as before', () async {
    final db = openHubDatabase(inMemory: true);
    addTearDown(db.close);
    final vault = SecretVault(db, 'a' * 64);
    await vault.put('spotify', 'token-1');
    expect((await db.select(db.secrets).getSingle()).value, isNot(startsWith('v2:')));
    expect(await vault.get('spotify'), 'token-1');
    expect(await SecretVault(db, 'b' * 64).get('spotify'), isNull, reason: 'another key opens nothing');
  });

  test('a chosen key is stretched and salted', () async {
    final db = openHubDatabase(inMemory: true);
    addTearDown(db.close);
    final vault = SecretVault(db, 'correct horse battery staple');
    await vault.put('google', 'refresh-2');
    expect((await db.select(db.secrets).getSingle()).value, startsWith('v2:'));
    expect(await vault.get('google'), 'refresh-2');
    expect(await db.kvGet('vault.salt'), isNotNull);
    expect(await SecretVault(db, 'correct horse battery stapler').get('google'), isNull);
  });

  test('an older seal under a chosen key still opens, and moves to v2', () async {
    final db = openHubDatabase(inMemory: true);
    addTearDown(db.close);
    await db.into(db.secrets).insert(SecretEntry(id: 'x', value: await legacySeal('family-secret', 'v'), updatedMs: 0));
    final vault = SecretVault(db, 'family-secret');
    expect(await vault.get('x'), 'v');
    expect((await db.select(db.secrets).getSingle()).value, startsWith('v2:'));
    expect(await vault.get('x'), 'v');
  });
}
