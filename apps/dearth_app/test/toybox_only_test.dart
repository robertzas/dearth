import 'package:dearth_app/app/grown_up.dart';
import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';

/// Toybox only (SPEC §7.2, FR-SET-01): a device set up as just one kid's
/// Toybox, with no Hub and nothing else on it.
void main() {
  Future<void> type(WidgetTester tester, String id, String text) => tester.enterText(find.descendant(of: byId(id), matching: find.byType(EditableText)), text);

  /// First run → "Just the Toybox" → Mia, 4, "Mama", PIN 2468.
  Future<AppHarness> toyboxOnly(WidgetTester tester, {Size size = const Size(1920, 1080)}) async {
    final h = await AppHarness.boot(tester, size: size);
    await h.settle();
    await tester.tap(byId('onboarding.toybox'));
    await h.settle(5);
    await type(tester, 'onboarding.toybox.kid', 'Mia');
    await tester.tap(byId('onboarding.toybox.age.4'));
    await type(tester, 'onboarding.toybox.grownup', 'Mama');
    await type(tester, 'onboarding.toybox.pin', '2468');
    await tester.tap(byId('onboarding.toybox.start'));
    await h.settle(40);
    return h;
  }

  testWidgets('FR-SET-01: "Just the Toybox" asks for a name, an age and a PIN, then opens straight into the Toybox', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.boot(tester);
    await h.settle();
    await tester.tap(byId('onboarding.toybox'));
    await h.settle(5);
    expectNoFallbackText();
    // Nothing filled in yet: it says what's missing and stays.
    await tester.tap(byId('onboarding.toybox.start'));
    await h.settle(3);
    expect(labelOf(tester, 'onboarding.error'), contains('name'));
    await type(tester, 'onboarding.toybox.kid', 'Mia');
    await tester.tap(byId('onboarding.toybox.age.4'));
    await type(tester, 'onboarding.toybox.pin', '24');
    await tester.tap(byId('onboarding.toybox.start'));
    await h.settle(3);
    expect(labelOf(tester, 'onboarding.error'), contains('PIN'));
    await type(tester, 'onboarding.toybox.grownup', 'Mama');
    await type(tester, 'onboarding.toybox.pin', '2468');
    await tester.tap(byId('onboarding.toybox.start'));
    await h.settle(40);

    final session = h.container.read(sessionProvider);
    expect(session.isToybox, isTrue);
    expect(session.isReady, isTrue);
    expect(byId('screen.toybox'), findsOneWidget);
    expect(labelOf(tester, 'toybox.title'), 'Mia’s Toybox');
    expect(find.byWidgetPredicate((w) => w is Semantics && (w.properties.identifier ?? '').startsWith('toybox.game.')), findsWidgets);
    expect(find.byWidgetPredicate((w) => w is Semantics && (w.properties.identifier ?? '').startsWith('nav.')), findsNothing, reason: 'no navigation bar');

    final people = (await tester.runAsync(() => h.db.select(h.db.profiles).get()))!;
    final mia = people.singleWhere((p) => p.role == ProfileRole.child);
    expect(mia.name, 'Mia');
    expect(mia.birthday, '2022-10-01', reason: 'four, as of October 2026');
    expect(mia.kidStage, KidStage.prek);
    final mama = people.singleWhere((p) => p.role == ProfileRole.adult);
    expect(mama.name, 'Mama');
    expect(verifyPin('2468', mama.pinHash!), isTrue);
    expectNoFallbackText();
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('SPEC §7.2: every other screen leads back to the Toybox; the settings show only what a Toybox needs', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await toyboxOnly(tester);
    final router = h.container.read(routerProvider);
    for (final place in ['/', '/calendar', '/meals', '/photos', '/settings/calendars']) {
      router.go(place);
      await h.settle(5);
      expect(byId('screen.toybox'), findsOneWidget, reason: place);
    }
    // The grown-up corner asks for the PIN; with it, the Toybox settings open.
    final ok = await tester.runAsync(() => h.container.read(grownUpProvider.notifier).unlock('2468'));
    expect(ok, isTrue);
    router.go('/settings/toybox');
    await h.settle(10);
    expect(byId('settings.nav.toybox'), findsOneWidget);
    expect(byId('settings.nav.people'), findsOneWidget);
    expect(byId('settings.nav.calendars'), findsNothing);
    expect(byId('settings.nav.recipes'), findsNothing);
    router.go('/settings/hub');
    await h.settle(10);
    expect(byId('hub.toybox'), findsOneWidget);
    expect(labelOf(tester, 'hub.leave'), contains('Leave Toybox mode'));
    await tester.tap(byId('settings.toybox'));
    await h.settle(10);
    expect(byId('screen.toybox'), findsOneWidget);
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('a game opens and is recorded on the device, as anywhere else', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await toyboxOnly(tester, size: const Size(1080, 1920));
    // The launcher's grid is lazy: drag until the tile is built, then
    // scroll it fully into view.
    final tile = byId('toybox.game.bubbles');
    await tester.dragUntilVisible(tile, find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first, const Offset(0, -180), maxIteration: 60);
    await tester.ensureVisible(tile);
    await h.settle(10);
    await tester.tap(tile);
    await h.settle(10);
    expect(byId('game.bubbles'), findsOneWidget);
    await tester.tap(byId('game.home'));
    await h.settle(10);
    expect(byId('screen.toybox'), findsOneWidget);
    await h.shutdown();
    handle.dispose();
  });
}
