import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_harness.dart';

/// Every dialog sits in one frame: the same dimmed barrier behind it and the
/// same background, whichever part of the app opened it.
void main() {
  ({Color? barrier, Color? background}) topDialog(WidgetTester tester) {
    final dialog = find.byType(Dialog).last;
    return (
      barrier: tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color,
      background: tester
          .widget<Material>(
            find.descendant(of: dialog, matching: find.byType(Material)).first,
          )
          .color,
    );
  }

  Future<void> close(WidgetTester tester, SessionHarness session) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await session.settle();
  }

  testSession('the dialogs share one barrier and one background', (
    tester,
    session,
  ) async {
    final seen = <String, ({Color? barrier, Color? background})>{};

    await tester.tap(find.byTooltip('User settings'));
    await session.settle();
    seen['user settings'] = topDialog(tester);
    await close(tester, session);

    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await session.settle();
    seen['connections'] = topDialog(tester);
    await tester.tap(find.text('Sign out'));
    await session.settle();
    seen['sign-out confirm'] = topDialog(tester);
    await close(tester, session);
    await close(tester, session);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await session.settle();
    seen['quick switcher'] = topDialog(tester);

    final dialogTheme = Theme.of(
      tester.element(find.byType(Dialog).last),
    ).dialogTheme;
    seen.forEach((name, dialog) {
      expect(dialog.barrier, dialogTheme.barrierColor, reason: name);
      expect(dialog.background, dialogTheme.backgroundColor, reason: name);
    });
    expect(dialogTheme.barrierColor, isNotNull);
    expect(dialogTheme.backgroundColor, isNotNull);
  });
}
