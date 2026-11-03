import 'package:flucord/src/presentation/widgets/count_badge.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

  Future<Finder> pumpBadge(WidgetTester tester, CountBadge badge) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: Center(child: badge)),
      ),
    );
    return find.byWidget(badge);
  }

  BoxDecoration decorationOf(WidgetTester tester, Finder badge) =>
      tester
              .widget<DecoratedBox>(
                find.descendant(of: badge, matching: find.byType(DecoratedBox)),
              )
              .decoration
          as BoxDecoration;

  testWidgets('a single digit is a 16 px pill in the danger colour', (
    tester,
  ) async {
    final badge = await pumpBadge(tester, const CountBadge(count: 3));

    final size = tester.getSize(badge);
    expect(size.height, 16);
    expect(size.width, greaterThanOrEqualTo(16));
    expect(decorationOf(tester, badge).color, surfaces.danger);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a long count grows wider but stays 16 px high', (tester) async {
    final badge = await pumpBadge(tester, const CountBadge(count: 120));

    expect(find.text('99+'), findsOneWidget);
    final size = tester.getSize(badge);
    expect(size.height, 16);
    expect(size.width, greaterThan(16));
  });

  testWidgets('digits are SemiBold', (tester) async {
    await pumpBadge(tester, const CountBadge(count: 7));

    expect(
      tester.widget<Text>(find.text('7')).style?.fontWeight,
      FontWeight.w600,
    );
  });

  testWidgets('the ring is 2 px in the colour behind the badge', (
    tester,
  ) async {
    final badge = await pumpBadge(
      tester,
      CountBadge(count: 3, ring: surfaces.rail),
    );

    final border = decorationOf(tester, badge).border! as Border;
    expect(border.top.color, surfaces.rail);
    expect(border.top.width, 2);
    // The ring is drawn outside the pill, so it never changes its size.
    expect(tester.getSize(badge).height, 16);
  });

  testWidgets('a neutral count takes the fill and digit colours it is given', (
    tester,
  ) async {
    final badge = await pumpBadge(
      tester,
      CountBadge(
        count: 4,
        color: surfaces.control,
        textColor: surfaces.text,
      ),
    );

    expect(decorationOf(tester, badge).color, surfaces.control);
    expect(tester.widget<Text>(find.text('4')).style?.color, surfaces.text);
  });
}
