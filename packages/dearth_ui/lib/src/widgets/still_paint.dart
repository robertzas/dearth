import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Scenery that doesn't move (a game's sky and grass, a board, a deck of
/// card backs): [painter] is painted once into an image the size of the box
/// on screen and shown from there (SPEC §12.2), again only when the painter
/// says it should repaint or the box changes size.
///
/// Impeller keeps no raster cache, so whatever is on screen is drawn again
/// on every frame anything moves. On the kitchen frame's GPU a diagonal
/// gradient over the screen, or a gradient filling a path, costs 30–60 ms
/// a frame that way: Memory Match's backdrop and card backs, Shape Sorter's
/// board and Counting Garden's hill held their games under 15 fps while a
/// card turned or a hint ring breathed. An image the same size costs what a
/// flat fill does.
///
/// Boxes with the same [shareKey] and size share one image: the caller
/// promises their painters paint the same thing. A painter that draws past
/// its box (a drop shadow) names how far in [outset]: the image is clipped
/// to the box grown by that much.
class DStillPaint extends StatefulWidget {
  const DStillPaint({super.key, required this.painter, this.shareKey, this.outset = EdgeInsets.zero});
  final CustomPainter painter;
  final Object? shareKey;
  final EdgeInsets outset;

  /// Paint into images (off on the web, whose renderer keeps its own
  /// cache). The perf probes switch it to compare the two.
  static bool rasterize = !kIsWeb;

  /// Memory for images shared by [shareKey] (RGBA, 4 bytes a pixel).
  static int sharedBudgetBytes = 16 << 20;

  static final LinkedHashMap<(Object, int, int), ui.Image> _shared = LinkedHashMap();
  static int _sharedBytes = 0;

  /// Lets every shared image go (tests).
  @visibleForTesting
  static void clearShared() {
    for (final i in _shared.values) {
      i.dispose();
    }
    _shared.clear();
    _sharedBytes = 0;
  }

  @override
  State<DStillPaint> createState() => _DStillPaintState();
}

class _DStillPaintState extends State<DStillPaint> {
  /// This widget's own handle on its image (a clone, when shared).
  ui.Image? _image;
  (int, int)? _pixels;

  @override
  void didUpdateWidget(DStillPaint old) {
    super.didUpdateWidget(old);
    if (widget.shareKey != old.shareKey || widget.outset != old.outset || widget.painter.shouldRepaint(old.painter)) _drop();
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    _image?.dispose();
    _image = null;
    _pixels = null;
  }

  ui.Image? _imageFor(Size size, double ratio) {
    final o = widget.outset;
    final pixels = (((size.width + o.horizontal) * ratio).ceil(), ((size.height + o.vertical) * ratio).ceil());
    if (pixels == _pixels && _image != null) return _image;
    _drop();
    final key = widget.shareKey;
    try {
      if (key == null) {
        _image = _paint(widget.painter, size, o, pixels);
      } else {
        final k = (key, pixels.$1, pixels.$2);
        var shared = DStillPaint._shared.remove(k);
        if (shared == null) {
          shared = _paint(widget.painter, size, o, pixels);
          DStillPaint._sharedBytes += pixels.$1 * pixels.$2 * 4;
        }
        DStillPaint._shared[k] = shared; // most recently used
        while (DStillPaint._sharedBytes > DStillPaint.sharedBudgetBytes && DStillPaint._shared.length > 1) {
          final oldest = DStillPaint._shared.keys.first;
          DStillPaint._sharedBytes -= oldest.$2 * oldest.$3 * 4;
          DStillPaint._shared.remove(oldest)!.dispose();
        }
        _image = shared.clone();
      }
    } on Object {
      return null;
    }
    _pixels = pixels;
    return _image;
  }

  static ui.Image _paint(CustomPainter painter, Size size, EdgeInsets outset, (int, int) pixels) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixels.$1 / (size.width + outset.horizontal), pixels.$2 / (size.height + outset.vertical))
      ..translate(outset.left, outset.top);
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    // Synchronous: drawn on the GPU when first shown, never a blank frame.
    final image = picture.toImageSync(pixels.$1, pixels.$2);
    picture.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final image = DStillPaint.rasterize && size.isFinite && !size.isEmpty ? _imageFor(size, MediaQuery.devicePixelRatioOf(context)) : null;
        if (image == null) return CustomPaint(isComplex: true, painter: widget.painter, size: size.isFinite ? size : Size.zero);
        final o = widget.outset;
        final raw = RawImage(image: image, width: size.width + o.horizontal, height: size.height + o.vertical, fit: BoxFit.fill, filterQuality: FilterQuality.low);
        if (o == EdgeInsets.zero) return raw;
        return SizedBox.fromSize(
          size: size,
          child: Stack(clipBehavior: Clip.none, children: [Positioned(left: -o.left, top: -o.top, child: raw)]),
        );
      });
}
