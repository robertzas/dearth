import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';
import '../../shared/recipe_visual.dart';
import '../calendar/event_editor.dart' show pickEmoji;
import '../photos/photos_data.dart';
import 'meal_ops.dart';

/// Writes a recipe of the family's own, or the family's version of any
/// recipe (SPEC FR-RCP-01: the family recipe box, hand-entered or edited).
/// Whatever is saved here is a recipe like any other: it scales, converts
/// units, plans, shops, cooks step by step with its timers, takes ratings,
/// turns up in search and in "Pairs with your plan". Returns the saved
/// recipe, or null if nothing was saved.
Future<RecipeData?> showRecipeEditor(BuildContext context, {RecipeData? recipe, Recipe? local}) => showDSheet<RecipeData>(
      context,
      id: 'recipe.editor',
      title: recipe == null ? 'New recipe' : 'Edit recipe',
      width: 760 * DTheme.of(context).scale,
      builder: (_) => _RecipeEditor(original: recipe, local: local),
    );

/// Food pictures for a recipe without a photo; Emoji 12 or older, which
/// the kitchen frame can draw.
const List<String> kRecipeEmojiChoices = [
  '🍝', '🍕', '🌮', '🌯', '🥗', '🍲', '🥣', '🍛', '🍜', '🍣', '🍱', '🥘', '🍳', '🥞', '🧇', '🥪', '🍔', '🌭', '🍟', '🥟', //
  '🍤', '🍗', '🍖', '🥩', '🐟', '🍚', '🍞', '🥐', '🥖', '🥨', '🥯', '🧀', '🥚', '🥕', '🥦', '🌽', '🍅', '🥑', '🍆', '🥔',
  '🍄', '🥬', '🍎', '🍌', '🍓', '🍑', '🍋', '🍰', '🎂', '🧁', '🥧', '🍪', '🍩', '🍫', '🍦', '🍮', '🥤', '🍵', '☕', '🍹',
];

/// A tag that is a picture (an emoji), as [recipeEmojiFor] reads it.
bool _isEmojiTag(String tag) => tag.isNotEmpty && tag.runes.first > 0x2000;

class _RecipeEditor extends ConsumerStatefulWidget {
  const _RecipeEditor({this.original, this.local});
  final RecipeData? original;
  final Recipe? local;

  @override
  ConsumerState<_RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<_RecipeEditor> {
  RecipeData? get _o => widget.original;
  bool get _own => (_o?.source ?? 'box') == 'box';

  late final _title = TextEditingController(text: _o?.title ?? '');
  late final _from = TextEditingController(text: _own ? (_o?.attribution ?? '') : '');
  late final _cuisine = TextEditingController(text: _o?.cuisine ?? '');
  late final _prep = TextEditingController(text: _o?.prepMin?.toString() ?? '');
  late final _cook = TextEditingController(text: _o?.cookMin?.toString() ?? '');
  late final _ingredients = TextEditingController(text: ingredientsText(_o?.ingredients ?? const []));
  late final _steps = TextEditingController(text: stepsText(_o?.steps ?? const []));
  late final _tags = TextEditingController(text: [for (final t in _o?.tags ?? const <String>[]) if (!_isEmojiTag(t) && t != kKidFriendlyTag) t].join(', '));
  late final _notes = TextEditingController(text: widget.local?.notes ?? '');

  late int _servings = _o?.servings ?? 4;
  late String? _course = _o?.category;
  late final Set<String> _diets = {...?_o?.diets};
  late bool _kid = _o?.tags.contains(kKidFriendlyTag) ?? false;
  late String? _emoji = _o?.tags.where(_isEmojiTag).firstOrNull;
  late String? _imageBlob = _o?.imageBlob;
  late String? _imageUrl = _o?.imageUrl;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _from, _cuisine, _prep, _cook, _ingredients, _steps, _tags, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Ingredient> get _parsed => parseIngredientsText(_ingredients.text, before: _o?.ingredients ?? const []);

  int? _minutes(TextEditingController c) {
    final n = int.tryParse(c.text.trim());
    return n == null || n <= 0 ? null : n;
  }

  /// The recipe as the form has it now.
  RecipeData _draft() {
    final o = _o;
    final prep = _minutes(_prep), cook = _minutes(_cook);
    final cuisine = _cuisine.text.trim();
    final from = _from.text.trim();
    return RecipeData(
      // A source's recipe keeps the id its local copy has (or would get),
      // so plans, ratings and the box all see one recipe.
      id: widget.local?.id ?? (o == null ? newId() : localRecipeId(o)),
      source: o?.source ?? 'box',
      sourceId: o?.sourceId,
      url: o?.url,
      title: _title.text.trim(),
      imageUrl: _imageUrl,
      imageBlob: _imageBlob,
      servings: _servings,
      prepMin: prep,
      cookMin: cook,
      totalMin: prep == null && cook == null ? o?.totalMin : (prep ?? 0) + (cook ?? 0),
      cuisine: cuisine.isEmpty ? null : cuisine,
      category: _course,
      tags: [?_emoji, if (_kid) kKidFriendlyTag, for (final t in parseTagsText(_tags.text)) if (!_isEmojiTag(t) && t != kKidFriendlyTag) t],
      diets: [for (final d in kRecipeDiets) if (_diets.contains(d)) d, for (final d in _diets) if (!kRecipeDiets.contains(d)) d],
      ingredients: _parsed,
      steps: parseStepsText(_steps.text),
      // Their own recipe says where it's from ("Grandma Rose"); a source's
      // keeps its credit.
      attribution: _own ? (from.isEmpty ? null : from) : o?.attribution,
      summary: o?.summary,
      alsoFrom: o?.alsoFrom ?? const [],
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    setState(() => _saving = true);
    final r = _draft();
    final w = ref.read(writerProvider);
    final notes = _notes.text.trim();
    await w.commit(saveFamilyRecipeOps(w.op, r, notes: notes.isEmpty ? null : notes, isNew: widget.local == null, nowMs: ref.read(appClockProvider).nowMs()));
    if (mounted) Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final draft = _draft();
    final parsed = draft.ingredients;
    final timers = draft.steps.fold<int>(0, (n, s) => n + stepTimers(s).length);
    Widget label(String s) => Padding(padding: EdgeInsets.only(top: t.space.lg, bottom: t.space.xs), child: Text(s.toUpperCase(), style: t.text.overline));
    void changed(String _) => setState(() {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecipeVisual(data: draft, title: draft.title.isEmpty ? 'Recipe' : draft.title, height: (t.isPhone ? 140 : 180) * t.scale),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.sm,
          runSpacing: t.space.sm,
          children: [
            DButton(label: 'Photo', icon: Icons.photo_outlined, tone: DButtonTone.tonal, size: DButtonSize.sm, id: 'recipe.editor.photo', onPressed: _pickPhoto),
            DButton(
              label: _emoji == null ? 'Picture' : 'Picture $_emoji',
              icon: Icons.emoji_food_beverage_outlined,
              tone: DButtonTone.tonal,
              size: DButtonSize.sm,
              id: 'recipe.editor.emoji',
              onPressed: () async {
                final e = await pickEmoji(context, choices: kRecipeEmojiChoices, title: 'Pick a picture');
                if (e != null) setState(() => _emoji = e);
              },
            ),
            if (_imageBlob != null || _imageUrl != null)
              DButton(
                label: 'No photo',
                icon: Icons.hide_image_outlined,
                tone: DButtonTone.ghost,
                size: DButtonSize.sm,
                id: 'recipe.editor.nophoto',
                onPressed: () => setState(() => _imageBlob = _imageUrl = null),
              ),
          ],
        ),
        SizedBox(height: t.space.md),
        DTextField(
          id: 'recipe.editor.title',
          controller: _title,
          hint: 'What’s it called?',
          big: true,
          autofocus: _o == null,
          errorText: _error,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_own) ...[
          SizedBox(height: t.space.sm),
          DTextField(id: 'recipe.editor.from', controller: _from, hint: 'Where it’s from (Grandma, a cookbook…)', textInputAction: TextInputAction.next),
        ],
        label('Servings and time'),
        Row(
          children: [
            DStepper(id: 'recipe.editor.servings', value: _servings, max: 24, format: (v) => '$v', onChanged: (v) => setState(() => _servings = v)),
            Text(_servings == 1 ? 'serving' : 'servings', style: t.text.caption),
          ],
        ),
        SizedBox(height: t.space.sm),
        Row(
          children: [
            Expanded(child: DTextField(id: 'recipe.editor.prep', controller: _prep, label: 'Prep minutes', keyboardType: TextInputType.number, onChanged: changed)),
            SizedBox(width: t.space.sm),
            Expanded(child: DTextField(id: 'recipe.editor.cook', controller: _cook, label: 'Cook minutes', keyboardType: TextInputType.number, onChanged: changed)),
          ],
        ),
        label('Kind'),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final c in kRecipeCourses)
              DChip(id: 'recipe.editor.course.${_slug(c)}', label: c, dense: true, selected: _course == c, onTap: () => setState(() => _course = _course == c ? null : c)),
          ],
        ),
        SizedBox(height: t.space.sm),
        DTextField(id: 'recipe.editor.cuisine', controller: _cuisine, hint: 'Cuisine (Mexican, Italian, Grandma’s…)', textInputAction: TextInputAction.next),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            DChip(id: 'recipe.editor.kid', label: 'Kid-friendly', emoji: '🧒', dense: true, selected: _kid, onTap: () => setState(() => _kid = !_kid)),
            for (final d in kRecipeDiets)
              DChip(
                id: 'recipe.editor.diet.${_slug(d)}',
                label: d[0].toUpperCase() + d.substring(1),
                dense: true,
                selected: _diets.contains(d),
                onTap: () => setState(() => _diets.contains(d) ? _diets.remove(d) : _diets.add(d)),
              ),
          ],
        ),
        label('Ingredients'),
        DTextField(
          id: 'recipe.editor.ingredients',
          controller: _ingredients,
          hint: '2 cups flour\n1 tsp salt\n\nFor the glaze:\n1 cup powdered sugar',
          maxLines: 14,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          onChanged: changed,
        ),
        SizedBox(height: t.space.xs),
        Text('One a line. A line ending in a colon starts a group.', style: t.text.caption.copyWith(color: t.colors.inkTertiary)),
        if (parsed.isNotEmpty) _Understood(ingredients: parsed),
        label('Steps'),
        DTextField(
          id: 'recipe.editor.steps',
          controller: _steps,
          hint: 'Heat the oven to 350°F.\nMix everything together.\nBake for 25 minutes.',
          maxLines: 14,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          onChanged: changed,
        ),
        SizedBox(height: t.space.xs),
        tid(
          'recipe.editor.stepcount',
          Text(
            draft.steps.isEmpty
                ? 'One step a line; cook mode shows them one at a time.'
                : '${draft.steps.length} step${draft.steps.length == 1 ? '' : 's'}${timers == 0 ? '' : ' · $timers timer${timers == 1 ? '' : 's'} for cook mode'}',
            style: t.text.caption.copyWith(color: t.colors.inkTertiary),
          ),
        ),
        label('Tags and notes'),
        DTextField(id: 'recipe.editor.tags', controller: _tags, hint: 'Tags, with commas (quick, freezer, birthday)'),
        SizedBox(height: t.space.sm),
        DTextField(
          id: 'recipe.editor.notes',
          controller: _notes,
          hint: 'Notes (used less salt, doubles well…)',
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        SizedBox(height: t.space.lg),
        Row(
          children: [
            Expanded(child: DButton(label: 'Cancel', tone: DButtonTone.neutral, expand: true, id: 'recipe.editor.cancel', onPressed: () => Navigator.of(context).pop())),
            SizedBox(width: t.space.sm),
            Expanded(
              child: DButton(label: _o == null ? 'Add recipe' : 'Save', icon: Icons.check_rounded, expand: true, busy: _saving, id: 'recipe.editor.save', onPressed: _save),
            ),
          ],
        ),
      ],
    );
  }

  /// A photo from the family's library (on a Hub), or a link to one.
  Future<void> _pickPhoto() async {
    final api = ref.read(hubApiProvider);
    final photos = api == null ? const <PhotoItem>[] : (ref.read(photoItemsProvider).value ?? const <PhotoItem>[]).take(60).toList();
    final link = TextEditingController(text: _imageUrl ?? '');
    final picked = await showDSheet<(String?, String?)>(
      context,
      id: 'recipe.photo.sheet',
      title: 'A photo for the recipe',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        final dpr = MediaQuery.devicePixelRatioOf(sheet);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photos.isNotEmpty && api != null) ...[
              Text('From your photos', style: t.text.title),
              SizedBox(height: t.space.sm),
              Wrap(
                spacing: t.space.xs,
                runSpacing: t.space.xs,
                children: [
                  for (final p in photos)
                    if (blobSha(p.thumbBlob) ?? blobSha(p.blobRef) case final sha?)
                      DPressable(
                        id: 'recipe.photo.${p.id}',
                        semanticLabel: p.caption ?? 'Photo',
                        borderRadius: BorderRadius.circular(10 * t.scale),
                        onTap: () => Navigator.of(sheet).pop((p.blobRef, null)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10 * t.scale),
                          child: SizedBox.square(
                            dimension: 96 * t.scale,
                            child: Image.network(
                              api.blobUrl(sha, width: (96 * t.scale * dpr).round(), height: (96 * t.scale * dpr).round(), cover: true).toString(),
                              fit: BoxFit.cover,
                              cacheWidth: (96 * t.scale * dpr).round(),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
              SizedBox(height: t.space.lg),
            ],
            Text('From a link', style: t.text.title),
            SizedBox(height: t.space.sm),
            DTextField(id: 'recipe.photo.link', controller: link, hint: 'https://…/photo.jpg', keyboardType: TextInputType.url),
            SizedBox(height: t.space.sm),
            DButton(label: 'Use this link', id: 'recipe.photo.uselink', onPressed: () => Navigator.of(sheet).pop((null, link.text.trim()))),
          ],
        );
      },
    );
    link.dispose();
    if (picked == null || !mounted) return;
    final (blob, url) = picked;
    setState(() {
      _imageBlob = blob;
      _imageUrl = url == null || url.isEmpty ? null : url;
    });
  }
}

/// What Dearth made of the ingredient lines: the amount it read (which
/// scales and converts) and the aisle it shops in, so a line it can't read
/// is plain before it reaches the list.
class _Understood extends StatelessWidget {
  const _Understood({required this.ingredients});
  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final amounts = ingredients.where((i) => i.qty != null).length;
    return Padding(
      padding: EdgeInsets.only(top: t.space.sm),
      child: DCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tid(
              'recipe.editor.understood',
              Text(
                '${ingredients.length} ingredient${ingredients.length == 1 ? '' : 's'} · $amounts with amounts that scale',
                style: t.text.label.copyWith(color: t.colors.inkSecondary),
              ),
            ),
            SizedBox(height: t.space.xs),
            for (final (n, i) in ingredients.indexed) ...[
              if (i.group != null && (n == 0 || ingredients[n - 1].group != i.group))
                Padding(padding: EdgeInsets.only(top: t.space.xs), child: Text(i.group!, style: t.text.label)),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 2 * t.scale),
                child: Row(
                  children: [
                    DEmoji(i.isStaple ? '🧂' : i.aisle.emoji, size: 18 * t.scale),
                    SizedBox(width: t.space.xs),
                    Expanded(
                      child: tid(
                        'recipe.editor.line.$n',
                        Text(
                          i.describe(),
                          style: t.text.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Text(i.isStaple ? 'pantry' : i.aisle.label, style: t.text.caption.copyWith(color: t.colors.inkTertiary)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _slug(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
