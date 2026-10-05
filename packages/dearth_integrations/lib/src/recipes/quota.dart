/// How often a provider's allowance starts over.
enum QuotaPeriod { hour, day, month }

/// A recipe provider's request allowance (SPEC FR-RCP-13). Counted here,
/// corrected from the provider's own "remaining" headers when it sends
/// them, and kept by the Hub across restarts ([toJson], [restore]). A
/// monthly allowance is spread over the month: by the end of day d, at most
/// d / (days in the month) of it may be spent, so quiet days save up for
/// busy ones but one evening of searching can't use the month.
class QuotaBudget {
  QuotaBudget({required this.limit, required this.period, this.spread = true, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final int limit;
  final QuotaPeriod period;
  final bool spread;
  final DateTime Function() _clock;

  /// Called after every change, so the Hub can save the count.
  void Function()? onChange;

  String _key = '';
  int _used = 0;

  /// Requests spent this period.
  int get used {
    _roll();
    return _used;
  }

  /// How many may have been spent by now (the whole limit, or the month's
  /// share up to the end of today).
  int get allowed {
    final now = _clock().toUtc();
    if (period != QuotaPeriod.month || !spread) return limit;
    final days = DateTime.utc(now.year, now.month + 1, 0).day;
    return (limit * now.day / days).ceil();
  }

  bool canSpend(int n) {
    _roll();
    return _used + n <= allowed;
  }

  void spend(int n) {
    _roll();
    _used += n;
    onChange?.call();
  }

  /// The provider says [remaining] are left this period.
  void observeRemaining(int remaining) {
    _roll();
    final used = limit - remaining;
    if (used > _used) {
      _used = used;
      onChange?.call();
    }
  }

  Map<String, Object?> toJson() {
    _roll();
    return {'period': _key, 'used': _used};
  }

  /// Picks up a saved count, if it's for this period.
  void restore(Map<String, Object?>? saved) {
    _roll();
    if (saved != null && saved['period'] == _key) _used = (saved['used'] as num?)?.toInt() ?? 0;
  }

  void _roll() {
    final t = _clock().toUtc();
    final key = switch (period) {
      QuotaPeriod.hour => '${t.year}-${t.month}-${t.day}T${t.hour}',
      QuotaPeriod.day => '${t.year}-${t.month}-${t.day}',
      QuotaPeriod.month => '${t.year}-${t.month}',
    };
    if (key != _key) {
      _key = key;
      _used = 0;
    }
  }
}
