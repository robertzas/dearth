import 'package:dearth_app/app/display_state.dart';
import 'package:dearth_app/features/photos/photos_data.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Text;

import 'support/app_harness.dart';

/// The photo frame and the night clock (SPEC §10.4 FR-SSV, §10.12 FR-DSP).
/// They render above the app's Navigator, so these also guard the layer's
/// Material (text style) and its own Navigator (sheets).
void main() {
  const sha = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9';

  Future<void> addPhoto(AppHarness h) => h.write((w) => [
        w.op('photo_sources', 'src-nas', {'kind': 'folder', 'name': 'Family NAS', 'enabled': true}),
        w.op('photo_items', 'ph-lake', {
          'source_id': 'src-nas',
          'blob_ref': sha,
          'taken_ms': DateTime.utc(2024, 7, 14, 18).millisecondsSinceEpoch,
          'width': 1600,
          'height': 1000,
          'location': 'Lake Dillon',
        }),
      ]);

  test('FR-PHO-01: one image in two sources shows once, the first copy kept', () {
    PhotoItem item(String id, String source, String? blob) =>
        PhotoItem(id: id, syncClock: '{}', syncHlc: '', syncSeq: 0, deleted: false, sourceId: source, blobRef: blob, hidden: false, favorite: false);
    final photos = uniquePhotos([item('a1', 'album', 'x'), item('b1', 'copy', 'x'), item('a2', 'album', 'y'), item('n', 'album', null)]);
    expect(photos.map((p) => p.id), ['a1', 'a2', 'n']);
  });

  testWidgets('FR-SSV-05: overlays and the night clock use themed text, never the fallback style', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    final display = h.container.read(displayProvider.notifier);
    display.startScreensaver();
    await h.settle();
    expect(byId('screensaver'), findsOneWidget);
    expect(byId('ss.clock'), findsOneWidget);
    expectNoFallbackText(byId('screensaver'));

    display.state = display.state.copyWith(mode: DisplayMode.night);
    await h.settle();
    expect(byId('nightclock'), findsOneWidget);
    expectNoFallbackText(byId('nightclock'));
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-PHO-09: a long press opens the photo’s source and date over the frame; hide skips it', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    await addPhoto(h);
    h.container.read(displayProvider.notifier).startScreensaver();
    await h.settle();

    await tester.longPress(byId('screensaver'));
    await h.settle();
    expect(byId('ss.options'), findsOneWidget, reason: 'no PINs in the demo, so the options open at once');
    final about = find.descendant(of: byId('ss.about'), matching: find.byType(Text));
    expect(tester.widget<Text>(about).data, 'July 2024 · Lake Dillon\nFrom Family NAS');
    expectNoFallbackText(byId('screensaver'));

    await tester.tap(byId('ss.hide'));
    await h.settle();
    final row = await tester.runAsync(() => (h.db.select(h.db.photoItems)..where((p) => p.id.equals('ph-lake'))).getSingle());
    expect(row!.hidden, isTrue);
    expect(byId('ss.options'), findsNothing);
    expect(byId('screensaver'), findsOneWidget, reason: 'choosing an option doesn’t wake the display');
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-PHO-09: with a PIN set, the grown-up PIN pad opens over the frame first', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    await addPhoto(h);
    final adult = await tester.runAsync(() => (h.db.select(h.db.profiles)..where((p) => p.role.equals(ProfileRole.adult))).get());
    await h.write((w) => [w.op('profiles', adult!.first.id, {'pin_hash': hashPin('2468', iterations: 1000)})]);
    h.container.read(displayProvider.notifier).startScreensaver();
    await h.settle();

    await tester.longPress(byId('screensaver'));
    await h.settle();
    expect(byId('grownup.sheet'), findsOneWidget);
    expect(byId('ss.options'), findsNothing);
    await h.shutdown();
    handle.dispose();
  });
}
