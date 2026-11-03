import 'package:flucord/src/app.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the composer hint names a person with @ and a channel with #', (
    tester,
  ) async {
    await _openDemo(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('message-composer')),
        matching: find.textContaining('Message #'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('member-row-mira')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('message-member')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining('Message @'), findsOneWidget);
    expect(find.textContaining('Message #'), findsNothing);
  });

  testWidgets('the emoji and sticker buttons use different icons', (
    tester,
  ) async {
    await _openDemo(tester);

    FlucordIconData iconOf(String key) => tester
        .widget<FlucordIcon>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(FlucordIcon),
          ),
        )
        .icon;

    expect(iconOf('open-sticker-picker'), isNot(iconOf('open-emoji-picker')));
  });
}

Future<void> _openDemo(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(FlucordApp.demo());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}
