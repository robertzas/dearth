import 'package:meta/meta.dart';

/// Major schema version carried by every op (SPEC §8.4.5). Bump only for
/// breaking schema changes; additive changes keep the major.
const int kSchemaMajor = 1;

enum OpKind {
  /// Field-level last-writer-wins upsert.
  upsert('u'),

  /// Create-once rows for append-only tables (ledger, game events…).
  insertOnly('i'),

  /// Tombstone: sets `deleted = true` with the op's HLC.
  delete('d');

  const OpKind(this.code);
  final String code;

  static OpKind fromCode(String code) =>
      values.firstWhere((k) => k.code == code, orElse: () => throw FormatException('Unknown op kind', code));
}

/// One replicated change (SPEC §8.4.2). Field values are JSON primitives:
/// String, num, bool or null. JSON columns carry their encoded text.
@immutable
class Op {
  const Op({
    required this.id,
    required this.table,
    required this.rowId,
    required this.kind,
    required this.fields,
    required this.hlc,
    this.actor,
    this.schema = kSchemaMajor,
  });

  /// Throws [FormatException] (never a `TypeError`) on a malformed op, so a
  /// receiver can drop that one op and keep going.
  factory Op.fromJson(Map<String, Object?> j) {
    final actor = j['a'], schema = j['v'];
    if (actor != null && actor is! String) throw FormatException('Op ${j['op']}: bad actor', actor);
    if (schema != null && schema is! num) throw FormatException('Op ${j['op']}: bad schema', schema);
    return Op(
      id: _req<String>(j, 'op'),
      table: _req<String>(j, 't'),
      rowId: _req<String>(j, 'id'),
      kind: OpKind.fromCode(_req<String>(j, 'k')),
      fields: Map<String, Object?>.from(_req<Map<String, Object?>>(j, 'f')),
      hlc: _req<String>(j, 'h'),
      actor: actor as String?,
      schema: (schema as num?)?.toInt() ?? kSchemaMajor,
    );
  }

  final String id;
  final String table;
  final String rowId;
  final OpKind kind;
  final Map<String, Object?> fields;
  final String hlc;

  /// `profile:<id>` for actions taken on behalf of a person (approvals…).
  final String? actor;
  final int schema;

  String? get actorProfileId => actor != null && actor!.startsWith('profile:') ? actor!.substring(8) : null;

  Map<String, Object?> toJson() => {
        'op': id,
        't': table,
        'id': rowId,
        'k': kind.code,
        'f': fields,
        'h': hlc,
        if (actor != null) 'a': actor,
        'v': schema,
      };

  @override
  String toString() => 'Op(${kind.code} $table/$rowId ${fields.keys.join(',')} @$hlc)';
}

/// An op as recorded by the Hub, with its global sequence number.
@immutable
class SeqOp {
  const SeqOp(this.seq, this.op);
  factory SeqOp.fromJson(Map<String, Object?> j) => SeqOp(_req<num>(j, 's').toInt(), Op.fromJson(_req<Map<String, Object?>>(j, 'o')));

  final int seq;
  final Op op;

  Map<String, Object?> toJson() => {'s': seq, 'o': op.toJson()};
}

T _req<T>(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is T) return v;
  throw FormatException('Op ${j['op'] ?? ''}: missing or bad "$key"', v);
}
