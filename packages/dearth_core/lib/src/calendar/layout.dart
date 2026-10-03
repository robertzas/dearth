import 'dart:math' as math;

import 'package:meta/meta.dart';

/// An item to place on a vertical time grid, in minutes from local midnight.
@immutable
class TimedItem<T> {
  const TimedItem(this.value, this.startMin, this.endMin);
  final T value;
  final int startMin;
  final int endMin;
}

/// A placed item: [column] of [columns] in its overlap cluster, spanning
/// [span] columns when free space to the right allows.
@immutable
class PlacedItem<T> {
  const PlacedItem(this.value, this.startMin, this.endMin, this.column, this.columns, this.span);
  final T value;
  final int startMin;
  final int endMin;
  final int column;
  final int columns;
  final int span;

  double get leftFraction => column / columns;
  double get widthFraction => span / columns;
}

/// Lays out overlapping events side by side (FR-CAL-05).
///
/// Items are clustered by transitive overlap; each cluster gets as many
/// columns as its maximum concurrency, items take the first free column, and
/// then expand right across columns that stay free for their whole duration.
/// [minDuration] gives very short events enough height to be tappable.
List<PlacedItem<T>> layoutDay<T>(List<TimedItem<T>> items, {int minDuration = 20}) {
  if (items.isEmpty) return const [];
  final sorted = [...items]
    ..sort((a, b) {
      final c = a.startMin.compareTo(b.startMin);
      return c != 0 ? c : (b.endMin - b.startMin).compareTo(a.endMin - a.startMin);
    });
  int endOf(TimedItem<T> i) => math.max(i.endMin, i.startMin + minDuration);

  final result = <PlacedItem<T>>[];
  var cluster = <TimedItem<T>>[];
  var clusterEnd = -1;

  void flush() {
    if (cluster.isEmpty) return;
    final columnEnds = <int>[];
    final columnOf = <TimedItem<T>, int>{};
    for (final item in cluster) {
      var col = columnEnds.indexWhere((end) => end <= item.startMin);
      if (col < 0) {
        col = columnEnds.length;
        columnEnds.add(endOf(item));
      } else {
        columnEnds[col] = endOf(item);
      }
      columnOf[item] = col;
    }
    final cols = columnEnds.length;
    for (final item in cluster) {
      final col = columnOf[item]!;
      var span = 1;
      for (var next = col + 1; next < cols; next++) {
        final blocked = cluster.any(
          (o) => columnOf[o] == next && o.startMin < endOf(item) && endOf(o) > item.startMin,
        );
        if (blocked) break;
        span++;
      }
      result.add(PlacedItem(item.value, item.startMin, endOf(item), col, cols, span));
    }
    cluster = [];
    clusterEnd = -1;
  }

  for (final item in sorted) {
    if (cluster.isNotEmpty && item.startMin >= clusterEnd) flush();
    cluster.add(item);
    clusterEnd = math.max(clusterEnd, endOf(item));
  }
  flush();
  return result;
}
