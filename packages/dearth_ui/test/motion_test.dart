import 'dart:async';

import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// SPEC §12.2/12.3: ambient motion at the tier's rate, and emoji drawn from
/// cached images.
void main() {
  group('AmbientTicker', () {
    /// Ticks in a second of 60 Hz frames.
    Future<int> run(WidgetTester tester, int fps) async {
      var ticks = 0;
      final ticker = AmbientTicker(tester, (_) => ticks++, fps: () => fps);
      unawaited(ticker.start());
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
      ticker.dispose();
      return ticks;
    }

    testWidgets('at 60 fps it ticks on every frame', (tester) async {
      expect(await run(tester, 60), greaterThanOrEqualTo(58));
    });

    testWidgets('at 30 fps it ticks about every other frame and asks for no frames in between', (tester) async {
      expect(await run(tester, 30), inInclusiveRange(25, 35));
    });

    testWidgets('stop and dispose end it cleanly', (tester) async {
      var ticks = 0;
      final ticker = AmbientTicker(tester, (_) => ticks++, fps: () => 30);
      unawaited(ticker.start());
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      ticker.stop();
      final at = ticks;
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, at);
      expect(ticker.isActive, isFalse);
      ticker.dispose();
    });
  });

  group('DEmoji', () {
    test('image sizes come in steps, so near sizes share one', () {
      expect(EmojiImages.pixelsFor(3), 8);
      expect(EmojiImages.pixelsFor(97), 104);
      expect(EmojiImages.pixelsFor(100), 104);
      expect(EmojiImages.pixelsFor(129), 144);
      expect(EmojiImages.pixelsFor(2000), 512);
    });

    testWidgets('draws from a cached image, tinted for a shadow; text where images are off', (tester) async {
      EmojiImages.instance.clear();
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [DEmoji('🍎', size: 100), DEmoji('🍎', size: 100, tint: Color(0xFF000000))]),
      ));
      final images = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
      expect(images, hasLength(2));
      expect(images.last.color, const Color(0xFF000000));
      expect(images.first.image!.isCloneOf(images.last.image!), isTrue, reason: 'one cached image, two handles');
      DEmoji.rasterize = false;
      await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: DEmoji('🍎', size: 100)));
      expect(find.byType(RawImage), findsNothing);
      expect(find.text('🍎'), findsOneWidget);
      DEmoji.rasterize = true;
      await tester.pumpWidget(const SizedBox());
      EmojiImages.instance.clear();
    });

    testWidgets('the cache stays within its budget, oldest out first, and on-screen images survive', (tester) async {
      final saved = EmojiImages.budgetBytes;
      EmojiImages.budgetBytes = 3 * 104 * 104 * 4;
      EmojiImages.instance.clear();
      const faces = ['🐶', '🐱', '🦊', '🐸', '🐵'];
      await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Row(children: [for (final f in faces) DEmoji(f, size: 100)])));
      await tester.pump();
      // Five on screen, three in the cache: the first two were let go by the
      // cache but their widgets still hold their own handles and draw.
      expect(tester.takeException(), isNull);
      for (final i in tester.widgetList<RawImage>(find.byType(RawImage))) {
        expect(i.image!.debugDisposed, isFalse);
      }
      await tester.pumpWidget(const SizedBox());
      EmojiImages.instance.clear();
      EmojiImages.budgetBytes = saved;
    });
  });

  group('DStillPaint', () {
    testWidgets('paints once into an image the size of its box, and again only when the painter changes', (tester) async {
      final counts = <int, int>{};
      Widget at(int version, {double width = 200}) => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: SizedBox(width: width, height: 100, child: DStillPaint(painter: _Counting(version, counts)))),
          );
      await tester.pumpWidget(at(1));
      final first = tester.widget<RawImage>(find.byType(RawImage));
      expect((first.image!.width, first.image!.height), (200 * tester.view.devicePixelRatio, 100 * tester.view.devicePixelRatio));
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is _Counting), findsNothing, reason: 'shown from the image, not painted every frame');
      await tester.pumpWidget(at(1)); // a rebuild with an equal painter
      expect(counts, {1: 1});
      await tester.pumpWidget(at(2));
      expect(counts, {1: 1, 2: 1});
      await tester.pumpWidget(at(2, width: 300)); // a new size
      expect(counts, {1: 1, 2: 2});
      DStillPaint.rasterize = false;
      await tester.pumpWidget(at(2));
      expect(find.byType(RawImage), findsNothing);
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is _Counting), findsOneWidget);
      DStillPaint.rasterize = true;
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('boxes with one share key paint one image between them', (tester) async {
      DStillPaint.clearShared();
      final counts = <int, int>{};
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [for (var i = 0; i < 4; i++) SizedBox(width: 80, height: 100, child: DStillPaint(shareKey: _Counting, painter: _Counting(1, counts)))]),
      ));
      expect(counts, {1: 1});
      final images = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
      expect(images, hasLength(4));
      expect(images.first.image!.isCloneOf(images.last.image!), isTrue);
      await tester.pumpWidget(const SizedBox());
      DStillPaint.clearShared();
    });
  });
}

/// Counts how often each version is painted.
class _Counting extends CustomPainter {
  _Counting(this.version, this.counts);
  final int version;
  final Map<int, int> counts;

  @override
  void paint(Canvas canvas, Size size) {
    counts[version] = (counts[version] ?? 0) + 1;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF7067E8));
  }

  @override
  bool shouldRepaint(_Counting old) => old.version != version;
}
