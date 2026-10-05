import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';
import '../settings_screen.dart';

/// Where each keyed source's free key comes from.
const Map<String, String> _keyHelp = {
  'recipeapi': 'Sign up at recipeapi.io (free, no card) and copy the key from your dashboard. It starts with “sk_live_”. '
      'The free plan allows 500 requests a month for a family’s own use.',
  'tasty': 'Sign in at rapidapi.com, open the “Tasty” API by API Dojo, subscribe to the free BASIC plan (500 requests a month) '
      'and copy your X-RapidAPI-Key. Tasty is an unofficial API, so it may stop working one day.',
  'spoonacular': 'Sign up at spoonacular.com/food-api (free plan) and copy the API key from your console. '
      'The free plan allows about 50 points a day.',
};

/// Recipes (SPEC FR-RCP-01, FR-RCP-13): the free sources the Hub searches.
/// Every search asks all the sources that are on, at once, and blends what
/// they find. Sources that need a key work once one is added; keys go to
/// the Hub and never come back to a display.
class RecipesSection extends ConsumerStatefulWidget {
  const RecipesSection({super.key});

  @override
  ConsumerState<RecipesSection> createState() => _RecipesSectionState();
}

class _RecipesSectionState extends ConsumerState<RecipesSection> {
  List<Map<String, Object?>>? _sources;
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
      final list = [for (final s in r['recipes'] as List? ?? const []) if (s is Map<String, Object?>) s];
      if (mounted) {
        setState(() {
          _sources = list;
          _error = null;
        });
      }
    } on HubApiException catch (e) {
      if (mounted) setState(() => _error = e.friendly);
    }
  }

  Future<void> _set(HubApi api, String id, Map<String, Object?> change) async {
    try {
      await api.put('/api/admin/integrations/recipes', {'source': id, ...change});
      await _load();
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }

  Future<void> _askKey(HubApi api, Map<String, Object?> source) async {
    final id = source['id']! as String;
    final result = await showDSheet<(String, String)>(
      context,
      title: '${source['name']} key',
      builder: (sheet) => _KeySheet(help: _keyHelp[id] ?? 'Paste the key from the source’s website.', canRemove: source['hasKey'] == true),
    );
    switch (result) {
      case ('remove', _):
        await _set(api, id, {'apiKey': ''});
      case ('save', final key) when key.isNotEmpty:
        await _set(api, id, {'apiKey': key});
        ref.read(toastProvider).show('${source['name']} joins your recipe searches', emoji: '🍳');
      case _:
        break;
    }
  }

  /// "On", "Needs a key", "12 of 500 used this month".
  static String _status(Map<String, Object?> s) {
    final note = s['note'] as String? ?? '';
    if (s['on'] != true) return 'Off · $note';
    if (s['hasKey'] != true) return 'Needs a free key · $note';
    final quota = s['quota'];
    if (quota is Map && (quota['limit'] as num? ?? 0) > 0) return '${quota['used']} of ${quota['limit']} used this month · $note';
    return 'On · $note';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final api = ref.watch(hubApiProvider);
    final admin = ref.watch(sessionProvider).admin;
    const footer = 'Every search asks all the sources that are on, at once, and blends what they find into one list: '
        'the same dish from two places becomes one card. Only free sources; a monthly allowance is spread over the month.';
    if (api == null || !admin) {
      return SettingsGroup(
        title: 'Recipe sources',
        footer: api == null
            ? 'Recipe search runs on your Dearth Hub. Without one, Discover uses the recipes that come with Dearth.'
            : 'Recipe sources are set from the Hub’s admin display.',
        children: const [],
      );
    }
    final sources = _sources;
    return SettingsGroup(
      title: 'Recipe sources',
      footer: _error ?? footer,
      children: [
        if (sources == null && _error == null) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        for (final s in sources ?? const <Map<String, Object?>>[]) ...[
          DSwitchRow(
            id: 'recipes.source.${s['id']}',
            leading: DEmoji(s['hasKey'] == true ? '🍳' : '🔑', size: 28 * t.scale),
            title: s['name'] as String? ?? '',
            subtitle: _status(s),
            value: s['on'] == true,
            onChanged: (v) => _set(api, s['id']! as String, {'on': v}),
          ),
          if (s['needsKey'] == true)
            DListRow(
              id: 'recipes.key.${s['id']}',
              title: s['hasKey'] == true ? 'Change the ${s['name']} key' : 'Add a free ${s['name']} key',
              leading: SizedBox(width: 28 * t.scale),
              chevron: true,
              onTap: () => _askKey(api, s),
            ),
        ],
      ],
    );
  }
}

/// Where a key comes from, a field to paste it, and Save (or Remove). It
/// owns its text controller, which outlives the sheet's closing animation.
class _KeySheet extends StatefulWidget {
  const _KeySheet({required this.help, required this.canRemove});
  final String help;
  final bool canRemove;

  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.help, style: t.text.body),
        SizedBox(height: t.space.md),
        DTextField(id: 'recipes.key.input', controller: _input, hint: 'Paste the key', autofocus: true),
        SizedBox(height: t.space.lg),
        DButton(label: 'Save', expand: true, id: 'recipes.key.save', onPressed: () => Navigator.of(context).pop(('save', _input.text.trim()))),
        if (widget.canRemove) ...[
          SizedBox(height: t.space.sm),
          DButton(label: 'Remove the key', expand: true, tone: DButtonTone.outline, id: 'recipes.key.remove', onPressed: () => Navigator.of(context).pop(('remove', ''))),
        ],
      ],
    );
  }
}
