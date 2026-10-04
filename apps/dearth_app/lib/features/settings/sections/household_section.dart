import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/household.dart';
import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';
import '../settings_screen.dart';

/// Household basics (SPEC FR-SET-02): name, location, units, week, clock.
class HouseholdSection extends ConsumerWidget {
  const HouseholdSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final h = ref.watch(householdProvider).value;
    if (h == null) return const SizedBox.shrink();
    final writer = ref.read(writerProvider);
    Future<void> set(Map<String, Object?> f) => writer.upsert('households', Ids.household, f);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Family',
          children: [
            DListRow(
              id: 'household.name',
              title: 'Name',
              subtitle: h.name,
              chevron: true,
              onTap: () async {
                final v = await _prompt(context, 'Household name', h.name);
                if (v != null && v.isNotEmpty) await set({'name': v});
              },
            ),
            DListRow(
              id: 'household.location',
              title: 'Location',
              subtitle: h.locationLabel ?? 'Not set — needed for weather and sunset',
              chevron: true,
              onTap: () => _pickLocation(context, ref),
            ),
            DListRow(title: 'Time zone', subtitle: h.timezone),
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
        SettingsGroup(
          title: 'Formats',
          children: [
            ChoiceRow<String>(
              title: 'Units',
              idPrefix: 'household.units',
              options: const [('imperial', '°F · in'), ('metric', '°C · mm')],
              value: h.units,
              onChanged: (v) => set({'units': v}),
            ),
            ChoiceRow<int>(
              title: 'Week starts on',
              idPrefix: 'household.weekstart',
              options: const [(7, 'Sunday'), (1, 'Monday'), (6, 'Saturday')],
              value: h.weekStart,
              onChanged: (v) => set({'week_start': v}),
            ),
            ChoiceRow<bool>(
              title: 'Clock',
              idPrefix: 'household.clock',
              options: const [(false, '12 h'), (true, '24 h')],
              value: h.clock24,
              onChanged: (v) => set({'clock24': v}),
            ),
          ],
        ),
        SizedBox(height: t.space.md),
      ],
    );
  }

  Future<void> _pickLocation(BuildContext context, WidgetRef ref) async {
    final api = ref.read(hubApiProvider);
    final query = TextEditingController();
    final picked = await showDSheet<Map<String, Object?>>(
      context,
      title: 'Where do you live?',
      id: 'household.location.sheet',
      builder: (sheet) => _LocationSearch(api: api, controller: query),
    );
    query.dispose();
    if (picked == null) return;
    await ref.read(writerProvider).upsert('households', Ids.household, {
      'lat': picked['lat'],
      'lon': picked['lon'],
      'location_label': picked['label'],
      'postal_code': ?picked['postalCode'],
      'country_code': ?picked['countryCode'],
      if (picked['timezone'] != null) 'timezone': picked['timezone'],
    });
  }
}

class _LocationSearch extends StatefulWidget {
  const _LocationSearch({required this.api, required this.controller});
  final HubApi? api;
  final TextEditingController controller;

  @override
  State<_LocationSearch> createState() => _LocationSearchState();
}

class _LocationSearchState extends State<_LocationSearch> {
  List<Map<String, Object?>> _results = const [];
  bool _busy = false;
  String? _error;

  Future<void> _search() async {
    final q = widget.controller.text.trim();
    if (q.isEmpty) return;
    final api = widget.api;
    if (api == null) {
      setState(() => _error = 'Location search runs on the Hub. In demo mode the family lives in Aurora, CO.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final list = await api.getList('/api/geo/search', {'q': q});
      setState(() => _results = list);
    } on Object catch (e) {
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DTextField(
          id: 'location.query',
          controller: widget.controller,
          hint: 'ZIP code or city',
          autofocus: true,
          onSubmitted: (_) => _search(),
          suffix: Padding(padding: EdgeInsets.all(t.space.xxs), child: DButton(label: 'Search', size: DButtonSize.sm, busy: _busy, onPressed: _search)),
        ),
        if (_error != null) Padding(padding: EdgeInsets.only(top: t.space.sm), child: Text(_error!, style: t.text.caption)),
        SizedBox(height: t.space.sm),
        for (final r in _results)
          DListRow(
            id: 'location.result',
            title: '${r['label']}',
            subtitle: '${r['timezone'] ?? ''}',
            leading: const DEmoji('📍', size: 28),
            onTap: () => Navigator.of(context).pop(r),
          ),
      ],
    );
  }
}

/// A one-line text prompt in a sheet.
Future<String?> _prompt(BuildContext context, String title, String initial) async {
  final c = TextEditingController(text: initial);
  final ok = await showDSheet<bool>(
    context,
    title: title,
    builder: (sheet) {
      final t = DTheme.of(sheet);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DTextField(controller: c, autofocus: true, big: true, onSubmitted: (_) => Navigator.of(sheet).pop(true)),
          SizedBox(height: t.space.md),
          DButton(label: 'Save', expand: true, onPressed: () => Navigator.of(sheet).pop(true)),
        ],
      );
    },
  );
  final v = c.text.trim();
  c.dispose();
  return ok == true ? v : null;
}
