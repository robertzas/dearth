import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../http/fetcher.dart';

/// Imports a recipe from any web page with schema.org `Recipe` data
/// (JSON-LD, incl. `@graph`, or microdata). SPEC FR-RCP-01 / §13.6.
class RecipeImporter {
  RecipeImporter(this.fetcher);
  final Fetcher fetcher;

  Future<RecipeData> importUrl(Uri url) async {
    if (!url.isScheme('https') && !url.isScheme('http')) {
      throw ProviderException('web', 'Only http(s) links can be imported');
    }
    final page = await fetcher.getText('web', url, headers: {
      'Accept': 'text/html,application/xhtml+xml',
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140 Safari/537.36',
    });
    final recipe = parseRecipeHtml(page, url);
    if (recipe == null) throw ProviderException('web', 'No recipe data found on that page');
    return recipe;
  }
}

/// Parses a recipe from page HTML, or null when none is present.
RecipeData? parseRecipeHtml(String page, Uri url) {
  final doc = html_parser.parse(page);
  for (final script in doc.querySelectorAll('script[type="application/ld+json"]')) {
    Object? data;
    try {
      data = jsonDecode(script.text.trim());
    } on FormatException {
      continue;
    }
    final node = _findRecipe(data);
    if (node != null) return _fromJsonLd(node, url, doc);
  }
  return _fromMicrodata(doc, url);
}

Map<String, Object?>? _findRecipe(Object? data) {
  if (data is List) {
    for (final d in data) {
      final r = _findRecipe(d);
      if (r != null) return r;
    }
  } else if (data is Map<String, Object?>) {
    final type = data['@type'];
    final isRecipe = type == 'Recipe' || (type is List && type.contains('Recipe'));
    if (isRecipe) return data;
    for (final key in const ['@graph', 'mainEntity', 'itemListElement']) {
      final r = _findRecipe(data[key]);
      if (r != null) return r;
    }
  }
  return null;
}

String? _text(Object? v) {
  if (v == null) return null;
  if (v is String) return _clean(v);
  if (v is List && v.isNotEmpty) return _text(v.first);
  if (v is Map) return _text(v['name'] ?? v['text'] ?? v['@value']);
  return '$v';
}

String _clean(String s) => html_parser.parseFragment(s).text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? s.trim();

String? _image(Object? v) {
  if (v is String) return v;
  if (v is List && v.isNotEmpty) return _image(v.last); // largest is usually last
  if (v is Map) return _image(v['url'] ?? v['contentUrl']);
  return null;
}

int? _minutes(Object? iso) {
  if (iso is! String) return null;
  final m = RegExp(r'P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?', caseSensitive: false).firstMatch(iso);
  if (m == null) return null;
  final total = int.parse(m[1] ?? '0') * 1440 + int.parse(m[2] ?? '0') * 60 + int.parse(m[3] ?? '0');
  return total == 0 ? null : total;
}

int _servings(Object? y) {
  if (y is num) return y.toInt().clamp(1, 100);
  final s = y is List ? y.map((e) => '$e').join(' ') : '$y';
  final n = RegExp(r'\d+').firstMatch(s);
  return n == null ? 4 : int.parse(n[0]!).clamp(1, 100);
}

List<String> _instructions(Object? v) {
  final out = <String>[];
  void walk(Object? node) {
    if (node == null) return;
    if (node is String) {
      out.addAll(node.split(RegExp(r'\n+|(?<=\.)\s{2,}')).map(_clean).where((s) => s.isNotEmpty));
    } else if (node is List) {
      node.forEach(walk);
    } else if (node is Map) {
      if (node['itemListElement'] != null) {
        walk(node['itemListElement']);
      } else {
        final t = _text(node['text'] ?? node['name']);
        if (t != null && t.isNotEmpty) out.add(t);
      }
    }
  }

  walk(v);
  return out;
}

List<String> _strings(Object? v) {
  if (v is String) return v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (v is List) return v.map(_text).whereType<String>().where((s) => s.isNotEmpty).toList();
  return const [];
}

RecipeData _fromJsonLd(Map<String, Object?> r, Uri url, dom.Document doc) {
  final lines = r['recipeIngredient'] ?? r['ingredients'];
  final ingredients = [
    for (final l in (lines is List ? lines : const <Object?>[]))
      if (_text(l) case final t? when t.isNotEmpty) parseIngredientLine(t),
  ];
  final host = url.host.replaceFirst('www.', '');
  final author = _text(r['author']);
  return RecipeData(
    id: 'web:${stableId('web', [url.toString()])}',
    source: 'web',
    sourceId: url.toString(),
    url: url.toString(),
    title: _text(r['name']) ?? doc.querySelector('title')?.text.trim() ?? 'Recipe',
    imageUrl: _image(r['image']),
    servings: _servings(r['recipeYield']),
    prepMin: _minutes(r['prepTime']),
    cookMin: _minutes(r['cookTime']),
    totalMin: _minutes(r['totalTime']),
    cuisine: _strings(r['recipeCuisine']).firstOrNull,
    category: _strings(r['recipeCategory']).firstOrNull,
    tags: _strings(r['keywords']).take(8).toList(),
    ingredients: ingredients,
    steps: _instructions(r['recipeInstructions']),
    summary: _text(r['description']),
    attribution: [host, if (author != null && author != host) author].join(' · '),
  );
}

RecipeData? _fromMicrodata(dom.Document doc, Uri url) {
  final scope = doc.querySelector('[itemtype*="schema.org/Recipe"]');
  if (scope == null) return null;
  String? prop(String name) {
    final el = scope.querySelector('[itemprop="$name"]');
    return el?.attributes['content'] ?? el?.text.trim();
  }

  final ingredients = [
    for (final el in scope.querySelectorAll('[itemprop="recipeIngredient"], [itemprop="ingredients"]'))
      if (el.text.trim().isNotEmpty) parseIngredientLine(_clean(el.text)),
  ];
  if (ingredients.isEmpty) return null;
  final steps = [
    for (final el in scope.querySelectorAll('[itemprop="recipeInstructions"]'))
      ..._instructions(el.text),
  ];
  return RecipeData(
    id: 'web:${stableId('web', [url.toString()])}',
    source: 'web',
    sourceId: url.toString(),
    url: url.toString(),
    title: prop('name') ?? 'Recipe',
    imageUrl: scope.querySelector('[itemprop="image"]')?.attributes['src'] ?? prop('image'),
    servings: _servings(prop('recipeYield')),
    totalMin: _minutes(prop('totalTime')),
    ingredients: ingredients,
    steps: steps,
    attribution: url.host.replaceFirst('www.', ''),
  );
}
