import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';

import '../http/fetcher.dart';
import 'recipe_provider.dart';

/// The Wikibooks Cookbook (no key; SPEC §13.6, FR-RCP-01): about 3,800
/// community recipes under CC BY-SA, read through the MediaWiki API. One
/// request searches the Cookbook namespace and brings back each hit's
/// wikitext, photo and address; a recipe comes from its "Recipe summary"
/// template and its Ingredients and Procedure sections. Pages without both
/// (ingredient and technique articles share the namespace) aren't recipes.
class WikibooksCookbook implements RecipeProvider {
  WikibooksCookbook(this.fetcher, {Uri? base}) : base = base ?? Uri.parse('https://en.wikibooks.org');

  final Fetcher fetcher;
  final Uri base;

  @override
  String get id => 'wikibooks';
  @override
  String get displayName => 'Wikibooks Cookbook';

  /// The Cookbook's namespace on Wikibooks.
  static const _namespace = '102';

  Future<List<RecipeData>> _pages(Map<String, String> params) async {
    final uri = base.replace(path: '/w/api.php', queryParameters: {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'prop': 'revisions|pageimages|info',
      'rvprop': 'content',
      'rvslots': 'main',
      'pithumbsize': '640',
      'inprop': 'url',
      ...params,
    });
    final j = await fetcher.getJson(id, uri);
    final pages = j is Map<String, Object?> && j['query'] is Map<String, Object?> ? (j['query']! as Map<String, Object?>)['pages'] : null;
    if (pages is! List) return const [];
    // Search hits carry their rank; keep it.
    final rows = pages.whereType<Map<String, Object?>>().toList()..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
    return [for (final p in rows) ?parsePage(p)];
  }

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    final words = [
      if (query.text?.trim().isNotEmpty ?? false) query.text!.trim(),
      ...query.includeIngredients,
      ?query.cuisine,
    ];
    if (words.isEmpty) return random(query.limit);
    final found = await _pages({'generator': 'search', 'gsrsearch': words.join(' '), 'gsrnamespace': _namespace, 'gsrlimit': '${query.limit.clamp(1, 20)}'});
    return [
      for (final r in found)
        if (!query.excludeIngredients.any((x) => r.ingredients.any((i) => i.key.contains(x.toLowerCase())))) r,
    ];
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) async {
    // Random Cookbook pages are often articles, not recipes: ask for more.
    final pages = await _pages({'generator': 'random', 'grnnamespace': _namespace, 'grnlimit': '${math.min(20, count * 3)}'});
    return pages.take(count).toList();
  }

  @override
  Future<RecipeData?> lookup(String sourceId) async => (await _pages({'titles': sourceId})).firstOrNull;

  @override
  Future<List<String>> cuisines() async => const [];

  /// One page as a recipe, or null when it isn't one.
  RecipeData? parsePage(Map<String, Object?> page) {
    final title = (page['title'] as String? ?? '').replaceFirst(RegExp('^Cookbook:'), '').trim();
    final revisions = page['revisions'];
    final slots = revisions is List && revisions.isNotEmpty && revisions.first is Map<String, Object?> ? (revisions.first as Map<String, Object?>)['slots'] : null;
    final main = slots is Map<String, Object?> ? slots['main'] : null;
    final text = main is Map<String, Object?> ? main['content'] as String? ?? '' : '';
    if (title.isEmpty || text.isEmpty) return null;

    final ingredients = <Ingredient>[];
    final steps = <String>[];
    String? section, group;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      final heading = RegExp(r'^(={2,4})\s*(.*?)\s*\1$').firstMatch(line);
      if (heading != null) {
        final name = wikiPlain(heading[2]!).toLowerCase();
        if (heading[1]!.length == 2) {
          section = name.contains('ingredient')
              ? 'ingredients'
              : RegExp('procedure|direction|method|preparation|instruction|steps').hasMatch(name)
                  ? 'steps'
                  : null;
          group = null;
        } else if (section == 'ingredients') {
          // "=== Marinade ingredients ===" → a group of its own.
          group = wikiPlain(heading[2]!).replaceFirst(RegExp(r'\s*ingredients?$', caseSensitive: false), '').trim();
        }
        continue;
      }
      if (section == 'ingredients' && line.startsWith('*')) {
        final item = wikiPlain(line.replaceFirst(RegExp(r'^\*+'), ''));
        if (item.isNotEmpty) ingredients.add(parseIngredientLine(item, group: group == null || group.isEmpty ? null : group));
      } else if (section == 'steps' && (line.startsWith('#') || line.startsWith('*'))) {
        final step = wikiPlain(line.replaceFirst(RegExp(r'^[#*:]+'), ''));
        if (step.isEmpty) continue;
        // "##" and "#*" lines belong to the step above them.
        if (RegExp(r'^[#*][#*:]').hasMatch(line) && steps.isNotEmpty) {
          steps[steps.length - 1] = '${steps.last} $step';
        } else {
          steps.add(step);
        }
      }
    }
    if (ingredients.isEmpty || steps.isEmpty) return null;

    final summary = templateParams(text, 'recipe summary');
    final thumb = page['thumbnail'];
    return RecipeData(
      id: providerRecipeId(id, title),
      source: id,
      sourceId: title,
      url: page['fullurl'] as String? ?? 'https://en.wikibooks.org/wiki/Cookbook:${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
      title: title.replaceAll(RegExp(r'\s+(I{1,3}|IV|V)$'), ''),
      imageUrl: thumb is Map<String, Object?> ? thumb['source'] as String? : null,
      servings: int.tryParse(RegExp(r'\d+').firstMatch(summary['servings'] ?? '')?[0] ?? '') ?? 4,
      totalMin: minutesIn(summary['time'] ?? ''),
      category: _category(summary['category']),
      cuisine: cuisineOf(text),
      ingredients: ingredients,
      steps: steps,
      attribution: 'the Wikibooks Cookbook (CC BY-SA 4.0)',
    );
  }

  /// "Curry recipes" → "Curry".
  static String? _category(String? c) {
    final s = wikiPlain(c ?? '').replaceFirst(RegExp(r'\s*recipes?$', caseSensitive: false), '').trim();
    return s.isEmpty ? null : s;
  }
}

/// Wikitext to plain text: links become their label, templates, files,
/// references, comments and markup go.
String wikiPlain(String s) {
  var t = s
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'<ref[^>]*/>'), '')
      .replaceAll(RegExp(r'<ref[^>]*>.*?</ref>', dotAll: true), '')
      .replaceAll(RegExp(r'\[\[(?:File|Image|Category):[^\]]*\]\]', caseSensitive: false), '');
  // {{convert|1|lb|kg}} → "1 lb"; other templates carry no recipe text.
  t = t.replaceAllMapped(RegExp(r'\{\{\s*convert\s*\|([^|}]*)\|([^|}]*)[^}]*\}\}', caseSensitive: false), (m) => '${m[1]!.trim()} ${m[2]!.trim()}');
  t = t.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
  t = t.replaceAllMapped(RegExp(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]'), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'\[https?://\S+\s+([^\]]*)\]'), (m) => m[1]!);
  t = t.replaceAll(RegExp("'{2,}"), '').replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&quot;', '"');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The `| key = value` parameters of the first `{{name …}}` template,
/// keys lowercased.
Map<String, String> templateParams(String text, String name) {
  final m = RegExp(r'\{\{\s*' + RegExp.escape(name) + r'\s*\|(.*?)\}\}', caseSensitive: false, dotAll: true).firstMatch(text);
  if (m == null) return const {};
  // Split on pipes that aren't inside [[links]].
  final body = m[1]!.replaceAllMapped(RegExp(r'\[\[[^\]]*\]\]'), (l) => l[0]!.replaceAll('|', '\u0000'));
  return {
    for (final part in body.split('|'))
      if (part.contains('='))
        part.substring(0, part.indexOf('=')).trim().toLowerCase(): part.substring(part.indexOf('=') + 1).replaceAll('\u0000', '|').trim(),
  };
}

/// "1 hour 30 minutes", "45 min", "1½ hours" → minutes.
int? minutesIn(String s) {
  final t = asciiFractions(s.toLowerCase());
  double total = 0;
  for (final m in RegExp(r'(\d+(?:\s+\d+/\d+|\.\d+|/\d+)?)\s*(hours?|hrs?|h\b|minutes?|mins?|m\b)').allMatches(t)) {
    final n = parseQuantity(m[1]!)?.value ?? 0;
    total += m[2]!.startsWith('h') ? n * 60 : n;
  }
  return total > 0 ? total.round() : null;
}

/// The cuisine a page links to ("Cuisine of India" → "Indian").
String? cuisineOf(String text) {
  final m = RegExp(r'\[\[Cookbook:Cuisine[ _]of[ _](?:the[ _])?([^\]|]+)', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  final place = m[1]!.replaceAll('_', ' ').trim();
  return _demonyms[place] ?? place;
}

const Map<String, String> _demonyms = {
  'India': 'Indian', 'Indonesia': 'Indonesian', 'China': 'Chinese', 'Japan': 'Japanese', 'Korea': 'Korean', 'Thailand': 'Thai', //
  'Vietnam': 'Vietnamese', 'Philippines': 'Filipino', 'Malaysia': 'Malaysian', 'Italy': 'Italian', 'France': 'French', 'Spain': 'Spanish',
  'Portugal': 'Portuguese', 'Greece': 'Greek', 'Germany': 'German', 'Mexico': 'Mexican', 'United States': 'American', 'Brazil': 'Brazilian',
  'Morocco': 'Moroccan', 'Ethiopia': 'Ethiopian', 'Turkey': 'Turkish', 'Lebanon': 'Lebanese', 'Iran': 'Persian', 'Russia': 'Russian',
  'Poland': 'Polish', 'Hungary': 'Hungarian', 'Ireland': 'Irish', 'United Kingdom': 'British', 'England': 'British', 'Jamaica': 'Jamaican',
  'Nigeria': 'Nigerian', 'Peru': 'Peruvian', 'Argentina': 'Argentinian', 'Cuba': 'Cuban', 'Pakistan': 'Pakistani', 'Sri Lanka': 'Sri Lankan',
};
