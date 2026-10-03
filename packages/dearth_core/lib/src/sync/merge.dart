import 'dart:convert';

import 'package:meta/meta.dart';

/// Result of merging one op into one row's field clock.
@immutable
class MergeResult {
  const MergeResult(this.changes, this.clock);

  /// Fields whose incoming value won and must be written.
  final Map<String, Object?> changes;

  /// The row's updated field → HLC map.
  final Map<String, String> clock;

  bool get changed => changes.isNotEmpty;
}

/// Field-level last-writer-wins merge (SPEC §8.4.2).
///
/// For each incoming field, the value is applied iff the op's HLC is strictly
/// greater than the HLC recorded for that field. Packed HLC strings compare
/// lexicographically in timestamp order, so plain string comparison suffices.
/// Pure and deterministic: every node converges regardless of arrival order.
MergeResult mergeFields({
  required Map<String, String> clock,
  required Map<String, Object?> fields,
  required String hlc,
  bool Function(String field)? isKnown,
}) {
  final changes = <String, Object?>{};
  final next = Map<String, String>.of(clock);
  fields.forEach((field, value) {
    if (isKnown != null && !isKnown(field)) return;
    final current = clock[field];
    if (current == null || hlc.compareTo(current) > 0) {
      changes[field] = value;
      next[field] = hlc;
    }
  });
  return MergeResult(changes, next);
}

Map<String, String> decodeClock(String? source) {
  if (source == null || source.isEmpty) return {};
  try {
    final v = jsonDecode(source);
    if (v is Map) return {for (final e in v.entries) '${e.key}': '${e.value}'};
  } on FormatException {
    // fall through
  }
  return {};
}

/// Canonical encoding (keys sorted) so equal clocks are byte-identical on
/// every replica.
String encodeClock(Map<String, String> clock) {
  final keys = clock.keys.toList()..sort();
  return jsonEncode({for (final k in keys) k: clock[k]});
}
