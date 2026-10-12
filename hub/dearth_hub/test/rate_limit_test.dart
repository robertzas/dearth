import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/src/jobs/basic_jobs.dart';
import 'package:dearth_hub/src/rate_limit.dart';
import 'package:dearth_hub/src/storage.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

/// The unauthenticated edges (SUGGESTIONS Hub §3).
void main() {
  test('a caller is limited within the window and free again after it', () {
    var now = 0;
    final limit = RateLimiter(3, const Duration(minutes: 10), now: () => now);
    for (var i = 0; i < 3; i++) {
      expect(limit.blocked('10.0.0.9'), isFalse);
      limit.hit('10.0.0.9');
    }
    expect(limit.blocked('10.0.0.9'), isTrue);
    expect(limit.blocked('10.0.0.7'), isFalse, reason: 'per caller');
    expect(limit.blocked(null), isFalse, reason: 'this machine is never limited');
    now += const Duration(minutes: 10).inMilliseconds + 1;
    expect(limit.blocked('10.0.0.9'), isFalse);
  });

  test('maintenance deletes pairing codes a day past their expiry', () async {
    final db = openHubDatabase(path: '', inMemory: true);
    addTearDown(db.close);
    const day = 86400000;
    const now = 100 * day;
    for (final (id, expires) in [('old', now - 2 * day), ('recent', now - day ~/ 2), ('live', now + 600000)]) {
      await db.into(db.pairings).insert(PairingsCompanion.insert(id: id, code: id.toUpperCase(), status: const Value('pending'), requestedMs: expires - 900000, expiresMs: expires));
    }
    expect(await expirePairings(db, nowMs: now), 1);
    expect((await db.select(db.pairings).get()).map((p) => p.id).toSet(), {'recent', 'live'});
  });
}
