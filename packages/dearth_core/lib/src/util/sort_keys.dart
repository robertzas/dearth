// Fractional sort keys (SPEC §8.3): rows order by a string key, and a new
// row gets a key between its neighbours, so devices never renumber.

/// A sort key that places a new row after [last] (fractional index, §8.3).
String sortKeyAfter(String? last) {
  if (last == null || last.isEmpty) return 'm';
  final code = last.codeUnitAt(last.length - 1);
  if (code < 0x7A) return last.substring(0, last.length - 1) + String.fromCharCode(code + 1);
  return '${last}m';
}

/// A key strictly between [a] and [b] (either may be null for the ends).
String sortKeyBetween(String? a, String? b) {
  final lo = a ?? '';
  if (b == null || b.isEmpty) return sortKeyAfter(lo.isEmpty ? null : lo);
  var i = 0;
  final out = StringBuffer();
  while (true) {
    final ca = i < lo.length ? lo.codeUnitAt(i) : 0x30; // '0'
    final cb = i < b.length ? b.codeUnitAt(i) : 0x7B;
    if (cb - ca > 1) {
      out.writeCharCode(ca + ((cb - ca) >> 1));
      return out.toString();
    }
    out.writeCharCode(ca);
    i++;
    if (i > 24) return '${out}m';
  }
}
