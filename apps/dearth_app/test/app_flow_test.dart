import 'package:dearth_app/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// App-level flows on a native in-memory database (SPEC §16.1 app logic).
void main() {
  testWidgets('FR-SET-01: first run shows onboarding; the demo leads Home', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.boot(tester);
    await h.settle();
    expect(byId('screen.onboarding'), findsOneWidget);
    await tester.tap(byId('onboarding.demo'));
    await h.settle(30);
    expect(h.container.read(sessionProvider).isDemo, isTrue);
    expect(byId('screen.home'), findsOneWidget);
    expectNoFallbackText();
    await h.shutdown();
    handle.dispose();
  });
}
