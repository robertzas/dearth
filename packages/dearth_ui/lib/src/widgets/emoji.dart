import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Renders an emoji glyph at a stable box size. Content icons (events,
/// chores, meals, weather for kids) all go through this widget (SPEC
/// §11.3).
///
/// Off the web, each emoji is drawn once into an image at its size on
/// screen and shown from there (SPEC §12.2). Drawn as text, a color emoji
/// that scales (a press, a pop-in, a celebration, a card turning) gets a
/// new glyph size every frame, and each one is decoded from the font and
/// uploaded to the GPU again: on the kitchen frame that made a card flip
/// take 100–400 ms a frame. An image scales for the cost of sampling it.
/// The web keeps text: its emoji font arrives lazily, and an image made
/// before it would stay blank.
class DEmoji extends StatefulWidget {
  const DEmoji(this.emoji, {super.key, required this.size, this.semanticLabel, this.tint});
  final String emoji;
  final double size;
  final String? semanticLabel;

  /// Draws the emoji's shape in this one color (a shadow, a silhouette).
  final Color? tint;

  /// Draw emoji from cached images (off by default on the web). The perf
  /// probes switch it to compare the two.
  static bool rasterize = !kIsWeb;

  @override
  State<DEmoji> createState() => _DEmojiState();
}

class _DEmojiState extends State<DEmoji> {
  /// This widget's own handle on the cached image: the cache may let its
  /// handle go while this one is still on screen.
  ui.Image? _image;
  (String, int)? _key;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  ui.Image? _imageFor(int px) {
    final key = (widget.emoji, px);
    if (key != _key) {
      _image?.dispose();
      _image = EmojiImages.instance.get(widget.emoji, px)?.clone();
      _key = key;
    }
    return _image;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget glyph;
    final px = EmojiImages.pixelsFor(size * MediaQuery.devicePixelRatioOf(context));
    final image = DEmoji.rasterize && size > 0 ? _imageFor(px) : null;
    if (image != null) {
      // A tint is a color filter on the image's draw: no layer of its own.
      glyph = RawImage(image: image, width: size, height: size, color: widget.tint, colorBlendMode: BlendMode.srcIn);
    } else {
      glyph = Center(child: Text(widget.emoji, textAlign: TextAlign.center, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, textScaler: TextScaler.noScaling, style: EmojiImages.style(size)));
      final tint = widget.tint;
      if (tint != null) glyph = ColorFiltered(colorFilter: ColorFilter.mode(tint, BlendMode.srcIn), child: glyph);
    }
    final box = SizedBox.square(dimension: size, child: glyph);
    return widget.semanticLabel == null ? ExcludeSemantics(child: box) : Semantics(label: widget.semanticLabel, child: ExcludeSemantics(child: box));
  }
}

/// Emoji drawn into images, least recently used first out past
/// [budgetBytes] (about 160 wall-sized emoji).
class EmojiImages {
  EmojiImages._();
  static final EmojiImages instance = EmojiImages._();

  /// Memory for the cached images (RGBA, 4 bytes a pixel).
  static int budgetBytes = 24 << 20;

  final LinkedHashMap<(String, int), ui.Image> _images = LinkedHashMap();
  int _bytes = 0;

  /// The text style a [size] box draws its emoji in (the box is a little
  /// bigger than the glyph, as it always was).
  static TextStyle style(double size) => TextStyle(fontSize: size * 0.86, height: 1.12, inherit: false, fontFamilyFallback: const ['Noto Color Emoji', 'Apple Color Emoji', 'Segoe UI Emoji']);

  /// Image sizes come in steps (8 px up to 128, then 16 px, at most 512), so
  /// near sizes share an image and a slow resize never makes dozens.
  static int pixelsFor(double devicePixels) {
    final p = devicePixels.clamp(8.0, 512.0);
    final step = p <= 128 ? 8 : 16;
    return ((p / step).ceil() * step).toInt();
  }

  /// [emoji] in a [px]-square image, or null when it can't be drawn.
  ui.Image? get(String emoji, int px) {
    final key = (emoji, px);
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit; // most recently used
      return hit;
    }
    final ui.Image image;
    try {
      image = _draw(emoji, px);
    } on Object {
      return null;
    }
    _images[key] = image;
    _bytes += px * px * 4;
    while (_bytes > budgetBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      _bytes -= oldest.$2 * oldest.$2 * 4;
      _images.remove(oldest)!.dispose();
    }
    return image;
  }

  static ui.Image _draw(String emoji, int px) {
    final painter = TextPainter(
      text: TextSpan(text: emoji, style: style(px.toDouble())),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, Offset((px - painter.width) / 2, (px - painter.height) / 2));
    painter.dispose();
    final picture = recorder.endRecording();
    // Synchronous: drawn on the GPU when first shown, never a blank frame.
    final image = picture.toImageSync(px, px);
    picture.dispose();
    return image;
  }

  /// Lets every cached image go (tests; a theme change doesn't need it).
  void clear() {
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    _bytes = 0;
  }
}
