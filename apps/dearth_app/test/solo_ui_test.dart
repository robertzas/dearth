import 'package:dearth_app/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';

/// "Run it on this device" (SPEC §7.2 Solo mode, FR-SET-01): the first-run
/// form. Starting the built-in Hub itself is covered in solo_test.dart (it
/// needs real sockets, which widget tests fake).
void main() {
  Future<void> type(WidgetTester tester, String id, String text) => tester.enterText(find.descendant(of: byId(id), matching: find.byType(EditableText)), text);

  Future<void> start(WidgetTester tester, AppHarness h) async {
    await tester.ensureVisible(byId('onboarding.solo.start'));
    await tester.tap(byId('onboarding.solo.start'));
    await h.settle(3);
  }

  testWidgets('FR-SET-01: "Run it on this device" asks for the household, a grown-up and a PIN before starting', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.boot(tester);
    await h.settle();
    expect(byId('onboarding.solo'), findsOneWidget, reason: 'native platforms can run the Hub inside the app');
    await tester.tap(byId('onboarding.solo'));
    await h.settle(5);
    expectNoFallbackText();
    await start(tester, h);
    expect(labelOf(tester, 'onboarding.error'), contains('household'));
    await type(tester, 'onboarding.solo.family', 'The Parkers');
    await start(tester, h);
    expect(labelOf(tester, 'onboarding.error'), contains('your name'));
    await type(tester, 'onboarding.solo.grownup', 'Sam');
    await type(tester, 'onboarding.solo.pin', '12');
    await start(tester, h);
    expect(labelOf(tester, 'onboarding.error'), contains('PIN'));
    expect(h.container.read(sessionProvider).isReady, isFalse, reason: 'nothing starts until the form is complete');
    await h.shutdown();
    handle.dispose();
  });
}
