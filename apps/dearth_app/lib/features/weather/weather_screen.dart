import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../home/home_card.dart';
import 'weather_chart.dart';

/// Weather (SPEC FR-WX-06): now, next hours, rain summary, 10 days, sun and
/// moon, alerts, what to wear. Stale data shows "as of" instead of blanks.
class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final report = ref.watch(weatherProvider).value;
    if (report == null) {
      return tid(
        'screen.weather',
        const Center(
          child: DEmptyState(
            emoji: '🌤️',
            title: 'Weather is on its way',
            message: 'Set your household location in Settings → Household. Dearth works without any API key.',
          ),
        ),
      );
    }
    final wide = !t.isPhone && MediaQuery.sizeOf(context).width > 1100 * t.scale;
    final g = t.gutter;
    final children = <Widget>[
      DPageHeader(title: 'Weather', subtitle: report.locationLabel),
      SizedBox(height: g),
      for (final a in report.alerts) ...[
        DBanner(
          id: 'weather.alert',
          tone: a.severityRank >= 3 ? DBannerTone.danger : DBannerTone.warning,
          emoji: '⚠️',
          title: a.event,
          message: a.headline ?? a.description,
          onTap: () => _showAlert(context, a),
        ),
        SizedBox(height: t.space.sm),
      ],
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _NowCard(report: report)),
            SizedBox(width: g),
            Expanded(flex: 2, child: _SunMoonCard(report: report)),
          ],
        )
      else ...[
        _NowCard(report: report),
        SizedBox(height: g),
      ],
      if (wide) SizedBox(height: g),
      _HoursCard(report: report),
      SizedBox(height: g),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _TenDayCard(report: report)),
            SizedBox(width: g),
            Expanded(flex: 2, child: Column(children: [_WearCard(report: report), SizedBox(height: g), _SourcesCard(report: report)])),
          ],
        )
      else ...[
        _TenDayCard(report: report),
        SizedBox(height: g),
        _SunMoonCard(report: report),
        SizedBox(height: g),
        _WearCard(report: report),
        SizedBox(height: g),
        _SourcesCard(report: report),
      ],
    ];
    return tid('screen.weather', ListView(padding: EdgeInsets.all(t.pageMargin), children: children));
  }

  void _showAlert(BuildContext context, WxAlert a) => showDSheet<void>(
        context,
        title: a.event,
        id: 'weather.alert.sheet',
        builder: (sheet) {
          final t = DTheme.of(sheet);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.headline != null) Text(a.headline!, style: t.text.bodyStrong),
              if (a.description != null) ...[SizedBox(height: t.space.sm), Text(a.description!, style: t.text.body)],
              if (a.instruction != null) ...[SizedBox(height: t.space.sm), Text(a.instruction!, style: t.text.body.copyWith(fontWeight: FontWeight.w700))],
              if (a.sender != null) ...[SizedBox(height: t.space.md), Text(a.sender!, style: t.text.caption)],
            ],
          );
        },
      );
}

class _NowCard extends ConsumerWidget {
  const _NowCard({required this.report});
  final WeatherReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final now = report.current;
    final imperial = ref.watch(imperialProvider);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final nowMs = ref.watch(nowMinuteMsProvider);
    if (now == null) return const SizedBox.shrink();
    final ageMin = ((nowMs - now.observedMs) / 60000).round();
    final stale = ageMin > 30;
    final source = now.isPersonalStation ? 'Your station ${now.stationName ?? now.source.substring(4)}' : (now.source.startsWith('nws') ? 'NWS ${now.stationName ?? ''}' : 'Open-Meteo');
    final today = report.dayFor(time.today().iso);
    final rain = nextRainWindow(report.hoursFrom(nowMs, 48));
    Widget stat(String emoji, String value, String label) => Container(
          constraints: BoxConstraints(minWidth: 132 * t.scale),
          padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
          decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: t.radius.card),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DEmoji(emoji, size: 26 * t.scale),
              SizedBox(width: t.space.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: t.text.label.copyWith(fontWeight: FontWeight.w800)),
                  Text(label, style: t.text.caption.copyWith(fontSize: 13 * t.scale)),
                ],
              ),
            ],
          ),
        );
    return HomeCard(
      id: 'weather.now',
      title: now.isPersonalStation ? 'In our backyard' : 'Right now',
      trailing: Text(stale ? formatAsOf(time.wall(now.observedMs), h24: h24) : '$source · ${ageMin <= 1 ? 'just now' : '$ageMin min ago'}', style: t.text.caption),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DEmoji(conditionEmoji(now.condition, isDay: now.isDay), size: 96 * t.scale),
              SizedBox(width: t.space.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tid('weather.now.temp', Text(formatTemp(now.tempC, imperial: imperial), style: t.text.display.copyWith(fontSize: 88 * t.scale))),
                  Text(
                    '${conditionLabel(now.condition)} · feels ${formatTemp(now.feelsLikeC ?? now.tempC, imperial: imperial)}'
                    '${today == null ? '' : ' · H ${formatTemp(today.highC, imperial: imperial)} L ${formatTemp(today.lowC, imperial: imperial)}'}',
                    style: t.text.body.copyWith(color: c.inkSecondary),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: t.space.md),
          Text(
            rain == null
                ? 'No rain expected in the next two days.'
                : '${rain.snow ? 'Snow' : 'Rain'} likely ${_windowLabel(rain, time, h24)}${rain.totalMm >= 0.2 ? ', about ${formatPrecip(rain.totalMm, imperial: imperial)}' : ''}.',
            style: t.text.bodyStrong,
          ),
          SizedBox(height: t.space.md),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              if (now.windKph != null) stat('💨', formatWind(now.windKph, imperial: imperial), now.gustKph == null ? 'wind' : 'gusts ${formatWind(now.gustKph, imperial: imperial)}'),
              if (now.humidity != null) stat('💧', '${now.humidity!.round()}%', 'humidity'),
              stat('🌧️', formatPrecip(now.precipTodayMm ?? 0, imperial: imperial), 'rain today'),
              if (now.uvIndex != null) stat('🕶️', now.uvIndex!.toStringAsFixed(0), 'UV index'),
              if (now.pressureHpa != null) stat('🧭', imperial ? '${(now.pressureHpa! * 0.02953).toStringAsFixed(2)} in' : '${now.pressureHpa!.round()} hPa', 'pressure'),
            ],
          ),
        ],
      ),
    );
  }

  String _windowLabel(RainWindow r, HouseholdTime time, bool h24) {
    final day = time.dateOfMs(r.startMs);
    final today = time.today();
    final dayName = day == today ? 'today' : (day == today.addDays(1) ? 'tomorrow' : weekdayLong(day));
    return '${formatTime(time.wall(r.startMs), h24: h24, compact: true)}–${formatTime(time.wall(r.endMs), h24: h24, compact: true)} $dayName';
  }
}

class _HoursCard extends ConsumerWidget {
  const _HoursCard({required this.report});
  final WeatherReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final imperial = ref.watch(imperialProvider);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final nowMs = ref.watch(nowMinuteMsProvider);
    final hours = report.hoursFrom(nowMs, t.isPhone ? 24 : 36);
    if (hours.isEmpty) return const SizedBox.shrink();
    final chart = HourlyChart(
      hours: hours,
      imperial: imperial,
      nowMs: nowMs,
      hourLabel: (ms) => ms <= nowMs ? 'Now' : formatTime(time.wall(ms), h24: h24, compact: true),
    );
    return HomeCard(
      id: 'weather.hours',
      title: 'Next ${hours.length} hours',
      child: t.isPhone
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: hours.length * 44 * t.scale, child: chart))
          : chart,
    );
  }
}

class _TenDayCard extends ConsumerWidget {
  const _TenDayCard({required this.report});
  final WeatherReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final imperial = ref.watch(imperialProvider);
    final today = ref.watch(todayProvider);
    final days = report.daily.where((d) => !(LocalDate.tryParse(d.date)?.isBefore(today) ?? true)).take(10).toList();
    if (days.isEmpty) return const SizedBox.shrink();
    final lows = days.map((d) => d.lowC).whereType<double>();
    final highs = days.map((d) => d.highC).whereType<double>();
    final min = lows.isEmpty ? 0.0 : lows.reduce(math.min);
    final max = highs.isEmpty ? 30.0 : highs.reduce(math.max);
    final nowTemp = report.current?.tempC;
    return HomeCard(
      id: 'weather.days',
      title: '${days.length} days',
      child: Column(
        children: [
          for (final d in days)
            Builder(builder: (context) {
              final date = LocalDate.parse(d.date);
              final isToday = date == today;
              return DPressable(
                id: 'weather.day.${d.date}',
                onTap: () => _showDay(context, ref, d),
                borderRadius: t.radius.card,
                pressedScale: 0.99,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space.xs),
                  child: Row(
                    children: [
                      SizedBox(width: 92 * t.scale, child: Text(isToday ? 'Today' : weekdayShort(date), style: t.text.bodyStrong)),
                      DEmoji(conditionEmoji(d.condition), size: 34 * t.scale),
                      SizedBox(width: t.space.sm),
                      SizedBox(
                        width: 64 * t.scale,
                        child: Text(
                          (d.precipProb ?? 0) >= 10 ? '${d.precipProb!.round()}%' : '',
                          style: t.text.label.copyWith(color: t.colors.vizRain, fontWeight: FontWeight.w800),
                        ),
                      ),
                      SizedBox(width: 52 * t.scale, child: Text(formatTemp(d.lowC, imperial: imperial), textAlign: TextAlign.right, style: t.text.label.copyWith(color: t.colors.inkSecondary))),
                      SizedBox(width: t.space.sm),
                      Expanded(
                        child: DRangeBar(
                          min: min,
                          max: max,
                          low: d.lowC ?? min,
                          high: d.highC ?? max,
                          now: isToday ? nowTemp : null,
                        ),
                      ),
                      SizedBox(width: t.space.sm),
                      SizedBox(width: 52 * t.scale, child: Text(formatTemp(d.highC, imperial: imperial), style: t.text.label.copyWith(fontWeight: FontWeight.w800))),
                      if (!t.isPhone)
                        SizedBox(
                          width: 92 * t.scale,
                          child: Text(
                            d.sunshineHours == null ? '' : '☀ ${d.sunshineHours!.toStringAsFixed(1)} h',
                            textAlign: TextAlign.right,
                            style: t.text.caption,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showDay(BuildContext context, WidgetRef ref, WxDay d) {
    final time = ref.read(householdTimeProvider);
    final imperial = ref.read(imperialProvider);
    final h24 = ref.read(clock24Provider);
    final date = LocalDate.parse(d.date);
    final hours = report.hourly.where((h) => time.dateOfMs(h.timeMs) == date).toList();
    showDSheet<void>(
      context,
      title: longDate(date),
      id: 'weather.day.sheet',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DEmoji(conditionEmoji(d.condition), size: 64 * t.scale),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${conditionLabel(d.condition)} · H ${formatTemp(d.highC, imperial: imperial)} L ${formatTemp(d.lowC, imperial: imperial)}', style: t.text.title),
                      Text(
                        [
                          if ((d.precipProb ?? 0) > 0) '${d.precipProb!.round()}% rain${(d.precipMm ?? 0) > 0 ? ', ${formatPrecip(d.precipMm, imperial: imperial)}' : ''}',
                          if (d.sunshineHours != null) '${d.sunshineHours!.toStringAsFixed(1)} h of sun',
                          if (d.uvMax != null) 'UV ${d.uvMax!.round()}',
                          if (d.windMaxKph != null) 'wind ${formatWind(d.windMaxKph, imperial: imperial)}',
                        ].join(' · '),
                        style: t.text.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (d.narrative != null) ...[SizedBox(height: t.space.md), Text(d.narrative!, style: t.text.body)],
            if (hours.isNotEmpty) ...[
              SizedBox(height: t.space.md),
              HourlyChart(
                hours: hours,
                imperial: imperial,
                nowMs: 0,
                hourLabel: (ms) => formatTime(time.wall(ms), h24: h24, compact: true),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SunMoonCard extends ConsumerWidget {
  const _SunMoonCard({required this.report});
  final WeatherReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final nowMs = ref.watch(nowMinuteMsProvider);
    final loc = ref.watch(householdLocationProvider) ?? (report.lat != null && report.lon != null ? (report.lat!, report.lon!) : null);
    final today = time.today();
    final day = report.dayFor(today.iso);
    final sun = loc == null ? null : sunTimesFor(today, loc.$1, loc.$2, time);
    final rise = day?.sunriseMs ?? sun?.sunriseMs;
    final set = day?.sunsetMs ?? sun?.sunsetMs;
    final moon = moonPhaseAt(nowMs);
    final progress = rise == null || set == null ? 0.5 : (nowMs - rise) / (set - rise);
    final daylight = rise != null && set != null ? ((set - rise) / 60000).round() : null;
    return HomeCard(
      id: 'weather.sun',
      title: 'Sun & moon',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 110 * t.scale, child: SunArc(progress: progress, isDay: progress > 0 && progress < 1)),
          SizedBox(height: t.space.xs),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sunrise', style: t.text.caption),
                    Text(rise == null ? '–' : formatTime(time.wall(rise), h24: h24), style: t.text.bodyStrong),
                  ],
                ),
              ),
              Column(
                children: [
                  Text('Daylight', style: t.text.caption),
                  Text(daylight == null ? '–' : '${daylight ~/ 60} h ${daylight % 60} m', style: t.text.bodyStrong),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Sunset', style: t.text.caption),
                    Text(set == null ? '–' : formatTime(time.wall(set), h24: h24), style: t.text.bodyStrong),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.md),
          Row(
            children: [
              DEmoji(moon.emoji, size: 40 * t.scale),
              SizedBox(width: t.space.sm),
              Expanded(child: tid('weather.moon', Text('${moon.name} · ${(moon.illumination * 100).round()}% lit', style: t.text.body))),
            ],
          ),
        ],
      ),
    );
  }
}

class _WearCard extends ConsumerWidget {
  const _WearCard({required this.report});
  final WeatherReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final today = ref.watch(todayProvider);
    final nowMs = ref.watch(nowMinuteMsProvider);
    final d = report.dayFor(today.iso);
    final hours = report.hoursFrom(nowMs, 12);
    final dayFeels = [for (final h in hours) if (h.isDay && h.tempC != null) h.tempC!];
    final feels = dayFeels.isEmpty ? (report.current?.feelsLikeC ?? report.current?.tempC ?? d?.lowC ?? 15) : dayFeels.reduce(math.min);
    final items = whatToWear(
      feelsLikeC: feels,
      precipProb: d?.precipProb ?? 0,
      precipMm: d?.precipMm ?? 0,
      snow: d?.condition.isSnowy ?? false,
      windKph: d?.windMaxKph ?? 0,
      uvMax: d?.uvMax ?? 0,
      sunny: d?.condition == WxCondition.clear || d?.condition == WxCondition.mostlyClear,
    );
    return HomeCard(
      id: 'weather.wear',
      title: 'What to wear today',
      child: Wrap(
        spacing: t.space.sm,
        runSpacing: t.space.sm,
        children: [
          for (final i in items)
            Container(
              padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
              decoration: BoxDecoration(color: t.colors.surfaceSunken, borderRadius: t.radius.pill),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [DEmoji(wearEmoji(i), size: 30 * t.scale), SizedBox(width: t.space.xs), Text(wearLabel(i), style: t.text.label)],
              ),
            ),
        ],
      ),
    );
  }
}

class _SourcesCard extends ConsumerWidget {
  const _SourcesCard({required this.report});
  final WeatherReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final sources = report.sources.values.toSet();
    final usesOpenMeteo = sources.any((s) => s.contains('open-meteo'));
    return HomeCard(
      id: 'weather.sources',
      title: 'Sources',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in report.sources.entries) Text('${e.key}: ${e.value}', style: t.text.caption),
          SizedBox(height: t.space.xs),
          Text('Updated ${formatTime(time.wall(report.fetchedMs), h24: h24)}', style: t.text.caption),
          if (usesOpenMeteo) Text('Weather data by Open-Meteo.com (CC BY 4.0)', style: t.text.caption),
        ],
      ),
    );
  }
}
