import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('navigates, searches, and sends a message', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const FlucordApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('The Forge'), findsOneWidget);
    expect(
      find.textContaining('Ship the vertical slice first'),
      findsOneWidget,
    );
    expect(find.text('transport-boundary.md'), findsOneWidget);
    expect(find.text('release-checklist'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('message-m4'))),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Reply'));
    await tester.pump();
    expect(find.text('Replying to Jack'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();
    expect(find.text('Connections'), findsOneWidget);
    expect(find.byKey(const ValueKey('discord-bot-token')), findsOneWidget);
    expect(find.textContaining('Personal account tokens'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('channel-forge-design')));
    await tester.pumpAndSettle();
    expect(find.textContaining('continuous signal'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('message-search')),
      'copper',
    );
    await tester.pump();
    expect(find.textContaining('copper only for warnings'), findsOneWidget);
    expect(find.textContaining('continuous signal'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('message-search')), '');
    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Native message path confirmed.',
    );
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Native message path confirmed.'), findsOneWidget);
  });
}
