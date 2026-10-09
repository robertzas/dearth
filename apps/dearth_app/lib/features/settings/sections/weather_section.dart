import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/household.dart';
import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';
import '../settings_screen.dart';

/// Weather: how often the Hub checks the forecast, and a family's own
/// Weather Underground station for the current conditions (SPEC FR-WX-01,
/// FR-WX-03, FR-WX-04). The key goes to the Hub and never comes back to a
/// display.
class WeatherSection extends ConsumerStatefulWidget {
  const WeatherSection({super.key});

  @override
  ConsumerState<WeatherSection> createState() => _WeatherSectionState();
}

class _WeatherSectionState extends ConsumerState<WeatherSection> {
  /// The Hub's station settings: hasKey, stationId, useWuForecast.
  Map<String, Object?>? _station;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(hubApiProvider);
    if (api == null || !ref.read(sessionProvider).admin) return;
    try {
      final r = await api.get('/api/admin/integrations');
      if (mounted) {
        setState(() {
          _station = r['weather'] as Map<String, Object?>? ?? const {};
          _error = null;
        });
      }
    } on HubApiException catch (e) {
      if (mounted) setState(() => _error = e.friendly);
    }
  }

  /// Saves [change] over the current station settings: the Hub resets any
  /// field a save leaves out.
  Future<void> _save(HubApi api, Map<String, Object?> change) async {
    final s = _station ?? const {};
    try {
      await api.put('/api/admin/integrations/weather', {'stationId': s['stationId'] ?? '', 'useWuForecast': s['useWuForecast'] ?? true, ...change});
      await _load();
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }

  Future<void> _askKey(HubApi api, bool hasKey) async {
    final result = await showDSheet<(String, String)>(
      context,
      title: 'Weather Underground key',
      builder: (sheet) => KeySheet(
        idPrefix: 'weather.key',
        help: 'Weather Underground gives a free API key to anyone who shares a personal weather station’s readings with it. '
            'Sign in at wunderground.com, open Member Settings → API Keys and copy the key.',
        canRemove: hasKey,
      ),
    );
    switch (result) {
      case ('remove', _):
        await _save(api, {'apiKey': ''});
      case ('save', final key) when key.isNotEmpty:
        await _save(api, {'apiKey': key});
      case _:
        break;
    }
  }

  Future<void> _pickStation(HubApi api, String current) async {
    final id = await showDSheet<String>(context, title: 'Weather station', builder: (sheet) => _StationSheet(api: api, current: current));
    if (id == null) return;
    await _save(api, {'stationId': id});
    if (id.isNotEmpty) ref.read(toastProvider).show('Current weather now comes from $id', emoji: '🌡️');
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final writer = ref.read(writerProvider);
    final api = ref.watch(hubApiProvider);
    final admin = ref.watch(sessionProvider.select((s) => s.admin));
    final station = _station;
    final hasKey = station?['hasKey'] == true;
    final stationId = (station?['stationId'] as String? ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Forecast',
          footer: 'The forecast comes from Open-Meteo, and in the US alerts from the National Weather Service: free, with no key. '
              'It’s for the household’s location (Settings → Household).',
          children: [
            ChoiceRow<int?>(
              title: 'Weather updates',
              subtitle: 'How often the Hub checks the forecast',
              idPrefix: 'household.weather',
              options: [for (final m in kWeatherRefreshChoices) (m, m < 60 ? '$m min' : '1 hour')],
              value: (ref.watch(settingMapProvider(SettingKeys.weatherRefresh))['minutes'] as num?)?.toInt() ?? 10,
              onChanged: (v) => writer.commit([settingOp(writer, SettingKeys.weatherRefresh, {'minutes': v})]),
            ),
          ],
        ),
        if (api == null || !admin)
          SettingsGroup(
            title: 'Your own weather station',
            footer: api == null ? 'A weather station connects through a Dearth Hub.' : 'The weather station is set from the Hub’s admin display.',
            children: const [],
          )
        else
          SettingsGroup(
            title: 'Your own weather station',
            footer: _error ??
                'A Weather Underground station near you, yours or a neighbor’s, gives the current conditions while its readings are fresh '
                    '(15 minutes or newer); otherwise the nearest official observation or the forecast does.',
            children: [
              if (station == null && _error == null) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              if (station != null) ...[
                DListRow(
                  id: 'weather.key',
                  title: hasKey ? 'Change the Weather Underground key' : 'Add a Weather Underground key',
                  leading: DEmoji(hasKey ? '🌡️' : '🔑', size: 28 * t.scale),
                  chevron: true,
                  onTap: () => _askKey(api, hasKey),
                ),
                if (hasKey) ...[
                  DListRow(
                    id: 'weather.station',
                    title: 'Station',
                    subtitle: stationId.isEmpty ? 'None yet: pick one to use your own readings' : stationId,
                    leading: SizedBox(width: 28 * t.scale),
                    chevron: true,
                    onTap: () => _pickStation(api, stationId),
                  ),
                  DSwitchRow(
                    id: 'weather.wuforecast',
                    leading: SizedBox(width: 28 * t.scale),
                    title: 'Use its 5-day forecast',
                    subtitle: 'Weather Underground’s forecast for the next five days; Open-Meteo for the rest',
                    value: station['useWuForecast'] as bool? ?? true,
                    onChanged: (v) => _save(api, {'useWuForecast': v}),
                  ),
                ],
              ],
            ],
          ),
      ],
    );
  }
}

/// A station by its ID, or one of the stations near the household (the
/// Hub asks Weather Underground). Pops the chosen ID, '' for none.
class _StationSheet extends StatefulWidget {
  const _StationSheet({required this.api, required this.current});
  final HubApi api;
  final String current;

  @override
  State<_StationSheet> createState() => _StationSheetState();
}

class _StationSheetState extends State<_StationSheet> {
  late final _input = TextEditingController(text: widget.current);
  List<Map<String, Object?>>? _near;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.getList('/api/admin/weather/stations').then((near) {
      if (mounted) setState(() => _near = near);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e is HubApiException ? e.friendly : 'Couldn’t find stations nearby.');
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final near = _near;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Type the station’s ID (it’s on its Weather Underground page, like KCOBOULD123) or pick one nearby.', style: t.text.body),
        SizedBox(height: t.space.md),
        DTextField(id: 'weather.station.input', controller: _input, hint: 'Station ID'),
        SizedBox(height: t.space.md),
        DButton(label: 'Use this station', expand: true, id: 'weather.station.save', onPressed: () => Navigator.of(context).pop(_input.text.trim().toUpperCase())),
        if (widget.current.isNotEmpty) ...[
          SizedBox(height: t.space.sm),
          DButton(label: 'Stop using a station', expand: true, tone: DButtonTone.outline, id: 'weather.station.clear', onPressed: () => Navigator.of(context).pop('')),
        ],
        SizedBox(height: t.space.lg),
        Text('NEARBY', style: t.text.overline),
        SizedBox(height: t.space.xs),
        if (_error != null)
          Text(_error!, style: t.text.caption)
        else if (near == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (near.isEmpty)
          Text('No stations near the household’s location.', style: t.text.caption)
        else
          for (final s in near.take(8))
            DListRow(
              id: 'weather.station.near.${s['id']}',
              title: '${s['id']}',
              subtitle: [if ('${s['name'] ?? ''}'.isNotEmpty) '${s['name']}', if (s['distanceKm'] case final num km) '${km.toStringAsFixed(1)} km away'].join(' · '),
              trailing: s['id'] == widget.current ? Icon(Icons.check_rounded, color: t.colors.accent) : null,
              onTap: () => Navigator.of(context).pop('${s['id']}'),
            ),
      ],
    );
  }
}
