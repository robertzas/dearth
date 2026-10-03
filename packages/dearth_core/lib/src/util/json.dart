import 'dart:convert';

/// Defensive JSON helpers for columns stored as JSON text. Corrupt or
/// unexpected values degrade to empty collections instead of throwing.

List<Object?> decodeJsonList(String? source) {
  if (source == null || source.isEmpty) return const [];
  try {
    final v = jsonDecode(source);
    return v is List ? v : const [];
  } on FormatException {
    return const [];
  }
}

Map<String, Object?> decodeJsonMap(String? source) {
  if (source == null || source.isEmpty) return const {};
  try {
    final v = jsonDecode(source);
    return v is Map<String, Object?> ? v : const {};
  } on FormatException {
    return const {};
  }
}

List<String> decodeStringList(String? source) =>
    decodeJsonList(source).whereType<String>().toList(growable: false);

List<Map<String, Object?>> decodeMapList(String? source) =>
    decodeJsonList(source).whereType<Map<String, Object?>>().toList(growable: false);

String encodeJson(Object? value) => jsonEncode(value);

/// Typed readers for loosely-typed maps (wire messages, provider payloads).
extension JsonRead on Map<String, Object?> {
  String? str(String key) {
    final v = this[key];
    return v is String ? v : (v == null ? null : '$v');
  }

  int? integer(String key) {
    final v = this[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? number(String key) {
    final v = this[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool? boolean(String key) {
    final v = this[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return null;
  }

  Map<String, Object?> obj(String key) {
    final v = this[key];
    return v is Map<String, Object?> ? v : const {};
  }

  List<Object?> arr(String key) {
    final v = this[key];
    return v is List ? v : const [];
  }
}
