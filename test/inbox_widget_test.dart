import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('exposes Inbox activity, tabs, dialog semantics, and dismissal', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpDesktopApp(tester);

    expect(find.bySemanticsLabel('Inbox, 2 mentions'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-mention-badge')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-inbox')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inbox-dialog')), findsOneWidget);
    final dialogSemantics = tester.getSemantics(
      find.byKey(const ValueKey('inbox-dialog')),
    );
    expect(dialogSemantics.label, 'Inbox');
    expect(find.text('Unreads  2'), findsOneWidget);
    expect(find.text('Mentions  1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inbox-unread-forge-design')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('close-inbox')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inbox-dialog')), findsNothing);
    semantics.dispose();
  });

  testWidgets('marks every unread row read and clears the header indicator', (
    tester,
  ) async {
    await _pumpDesktopApp(tester);
    await tester.tap(find.byKey(const ValueKey('open-inbox')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inbox-unread-forge-design')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inbox-unread-night-ops')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('inbox-mark-all-read')));
    await tester.pumpAndSettle();

    expect(find.text('You are all caught up'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-mark-all-read')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('close-inbox')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inbox-mention-badge')), findsNothing);
    expect(find.byKey(const ValueKey('inbox-unread-indicator')), findsNothing);
    expect(find.bySemanticsLabel('Inbox'), findsOneWidget);
  });

  testWidgets('opens a mention in its channel at the exact cached message', (
    tester,
  ) async {
    await _pumpDesktopApp(tester);
    await tester.tap(find.byKey(const ValueKey('open-inbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mentions  1'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('inbox-mention-design-mention')),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(const ValueKey('message-design-mention'));
    expect(target, findsOneWidget);
    final targetRect = tester.getRect(target);
    expect(targetRect.top, greaterThanOrEqualTo(0));
    expect(targetRect.bottom, lessThanOrEqualTo(900));
    expect(find.byKey(const ValueKey('inbox-dialog')), findsNothing);
  });
}

Future<void> _pumpDesktopApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const FlucordApp());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}
