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

  factory Op.fromJson(Map<String, Object?> j) => Op(
        id: j['op']! as String,
        table: j['t']! as String,
        rowId: j['id']! as String,
        kind: OpKind.fromCode(j['k']! as String),
        fields: Map<String, Object?>.from(j['f']! as Map),
        hlc: j['h']! as String,
        actor: j['a'] as String?,
        schema: (j['v'] as num?)?.toInt() ?? kSchemaMajor,
      );

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
  factory SeqOp.fromJson(Map<String, Object?> j) =>
      SeqOp((j['s']! as num).toInt(), Op.fromJson(Map<String, Object?>.from(j['o']! as Map)));

  final int seq;
  final Op op;

  Map<String, Object?> toJson() => {'s': seq, 'o': op.toJson()};
}
