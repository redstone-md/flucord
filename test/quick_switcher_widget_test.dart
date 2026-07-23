import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('opens globally and routes a keyboard selection', (tester) async {
    await _pumpWorkspace(tester);
    await tester.tap(find.byKey(const ValueKey('message-composer')));
    await tester.pump();

    await _openQuickSwitcher(tester);
    expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);
    expect(find.text('SERVERS'), findsOneWidget);
    expect(find.text('The Forge / #general'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('quick-switcher-search')),
      'radio-room',
    );
    await tester.pump();
    expect(find.text('Night Shift / radio-room'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);
    expect(find.text('Local media ready'), findsOneWidget);
  });

  testWidgets('moves the active destination with both arrow keys', (
    tester,
  ) async {
    await _pumpWorkspace(tester);
    await _openQuickSwitcher(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Night Shift'), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-night-ops')), findsOneWidget);
  });

  testWidgets('supports Escape, mouse routing, and activity semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpWorkspace(tester);

    await _openQuickSwitcher(tester);
    expect(
      find.bySemanticsLabel(
        'The Forge / #design, Text Channel, unread, 2 mentions',
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);

    await _openQuickSwitcher(tester);
    await tester.enterText(
      find.byKey(const ValueKey('quick-switcher-search')),
      'design',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('quick-switcher-textChannel:forge-design')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining('continuous signal'), findsOneWidget);
    semantics.dispose();
  });
}

Future<void> _pumpWorkspace(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const FlucordApp());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _openQuickSwitcher(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}
