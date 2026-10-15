import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child) => MaterialApp(
      theme: buildThemeData(DTheme(colors: DColors.light, scale: 1, displayClass: DisplayClass.wallL, policy: TierPolicy.of(PerfTier.t2))),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('DTheme is reachable through Theme.of (not shadowed by ThemeExtension.type)', (tester) async {
    late DTheme t;
    await tester.pumpWidget(host(Builder(builder: (context) {
      t = DTheme.of(context);
      return const SizedBox();
    })));
    expect(t.text.body.fontSize, 22);
    expect(t.space.touch, 64);
  });

  testWidgets('DButton fires on tap and not when disabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(Column(children: [
      DButton(label: 'Go', id: 'go', onPressed: () => taps++),
      const DButton(label: 'Off'),
    ])));
    await tester.tap(find.text('Go'));
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('§11.10 long-press needs ≥ 600 ms', (tester) async {
    var long = 0;
    var taps = 0;
    await tester.pumpWidget(host(DPressable(onTap: () => taps++, onLongPress: () => long++, child: const SizedBox(width: 100, height: 100))));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(DPressable)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(long, 0);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(long, 1);
    expect(taps, 0);
  });

  testWidgets('§9.3 hold-to-activate fires after the hold, never on a tap', (tester) async {
    var fired = 0;
    await tester.pumpWidget(host(DHoldToActivate(onActivated: () => fired++, child: const SizedBox(width: 80, height: 80))));
    await tester.tap(find.byType(DHoldToActivate));
    await tester.pumpAndSettle();
    expect(fired, 0);
    final g = await tester.startGesture(tester.getCenter(find.byType(DHoldToActivate)));
    await tester.pump(); // the ticker's first frame
    await tester.pump(const Duration(seconds: 3, milliseconds: 100));
    await g.up();
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('DPinPad submits after four digits and clears for the next try', (tester) async {
    final tries = <String>[];
    await tester.pumpWidget(host(DPinPad(onSubmit: (pin) async {
      tries.add(pin);
      return pin == '2468';
    })));
    for (final d in ['1', '1', '1', '1', '2', '4', '6', '8']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tries, ['1111', '2468']);
  });

  testWidgets('DSegmented reports the chosen option', (tester) async {
    String? chosen;
    await tester.pumpWidget(host(DSegmented<String>(options: const [('a', 'Day'), ('b', 'Week')], value: 'a', onChanged: (v) => chosen = v)));
    await tester.tap(find.text('Week'));
    expect(chosen, 'b');
  });

  testWidgets('a side sheet on a landscape wall ends above the on-screen keyboard', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(Builder(
      builder: (context) => DButton(
        label: 'Open',
        onPressed: () => showDSheet<void>(context, title: 'New chore', builder: (_) => const SizedBox(height: 2000, child: DTextField(hint: 'Voice'))),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final scroll = find.ancestor(of: find.byType(DTextField), matching: find.byType(SingleChildScrollView));
    expect(tester.getBottomLeft(scroll).dy, 1080);
    // The frame keeps its window full size under the keyboard (immersive),
    // so the keyboard arrives as a view inset.
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(scroll).dy, lessThanOrEqualTo(680));
  });

  testWidgets('DTextField: no auto-correct, and a tap elsewhere puts the keyboard away', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 400, child: DTextField(hint: 'Name', focusNode: focus)),
      const SizedBox(width: 400, height: 200),
    ])));
    expect(tester.widget<TextField>(find.byType(TextField)).autocorrect, isFalse);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });
}
