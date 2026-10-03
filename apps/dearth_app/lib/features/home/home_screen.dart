import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/household.dart';
import 'agenda_card.dart';
import 'home_header.dart';
import 'home_widgets.dart';

/// Home: the five-second glance (SPEC §10.1, §11.7). Layout follows the
/// display class; every widget is an independent repaint boundary.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final hasKids = ref.watch(kidsProvider).isNotEmpty;
    return tid(
      'screen.home',
      LayoutBuilder(builder: (context, box) {
        final m = t.pageMargin;
        final g = t.gutter;
        if (t.isPhone) return _PhoneHome(hasKids: hasKids);
        final landscape = box.maxWidth > box.maxHeight;
        if (landscape && box.maxWidth < 1500 * t.scale) {
          // Tablets in landscape: agenda beside one scrolling column.
          return Padding(
            padding: EdgeInsets.all(m),
            child: Column(
              children: [
                const HomeHeader(),
                SizedBox(height: g),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: AgendaCard()),
                      SizedBox(width: g),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            const UpNextCard(),
                            SizedBox(height: g),
                            const DinnerCard(),
                            if (hasKids) ...[SizedBox(height: g), const KidsCard()],
                            SizedBox(height: g),
                            const WeekStripCard(),
                            SizedBox(height: g),
                            const NotesCard(),
                            SizedBox(height: g),
                            const ShoppingCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        if (landscape) {
          return Padding(
            padding: EdgeInsets.all(m),
            child: Column(
              children: [
                const HomeHeader(),
                SizedBox(height: g),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(flex: 11, child: AgendaCard()),
                      SizedBox(width: g),
                      Expanded(
                        flex: 9,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const UpNextCard(),
                            SizedBox(height: g),
                            const WeekStripCard(),
                            SizedBox(height: g),
                            const Expanded(child: NotesCard(expand: true)),
                          ],
                        ),
                      ),
                      SizedBox(width: g),
                      Expanded(
                        flex: 9,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DinnerCard(imageHeight: (box.maxHeight > 900 * t.scale ? 168 : 120) * t.scale),
                            SizedBox(height: g),
                            if (hasKids) ...[const KidsCard(), SizedBox(height: g)],
                            const Expanded(child: ShoppingCard(expand: true)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        // Portrait walls and tablets: stacked, scrolling if needed.
        return ListView(
          padding: EdgeInsets.all(m),
          children: [
            const HomeHeader(),
            SizedBox(height: g),
            const UpNextCard(),
            SizedBox(height: g),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: AgendaCard(days: [0], expand: false)),
                SizedBox(width: g),
                const Expanded(child: AgendaCard(days: [1], expand: false, title: 'Tomorrow')),
              ],
            ),
            SizedBox(height: g),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: DinnerCard()),
                if (hasKids) ...[SizedBox(width: g), const Expanded(child: KidsCard())],
              ],
            ),
            SizedBox(height: g),
            const WeekStripCard(),
            SizedBox(height: g),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: NotesCard()),
                SizedBox(width: g),
                const Expanded(child: ShoppingCard()),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// The phone companion's Today (FR-CMP-02).
class _PhoneHome extends StatelessWidget {
  const _PhoneHome({required this.hasKids});
  final bool hasKids;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final g = t.space.md;
    return ListView(
      padding: EdgeInsets.all(t.pageMargin),
      children: [
        const HomeHeader(compact: true),
        SizedBox(height: g),
        const UpNextCard(),
        SizedBox(height: g),
        const AgendaCard(expand: false),
        SizedBox(height: g),
        const DinnerCard(),
        if (hasKids) ...[SizedBox(height: g), const KidsCard()],
        SizedBox(height: g),
        const ShoppingCard(),
        SizedBox(height: g),
        const NotesCard(),
        SizedBox(height: g),
        const WeekStripCard(),
      ],
    );
  }
}
