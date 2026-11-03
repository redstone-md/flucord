import 'package:flucord/src/app.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openDemo(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Color? iconColour(WidgetTester tester, String key) => tester
      .widget<FlucordIcon>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(FlucordIcon),
        ),
      )
      .color;

  final danger = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!.danger;

  testWidgets('the user panel is 52 px high', (tester) async {
    await openDemo(tester);

    expect(
      tester.getSize(find.byKey(const ValueKey('account-panel'))).height,
      52,
    );
  });

  testWidgets('mute, deafen and settings are 28 px buttons at the right', (
    tester,
  ) async {
    await openDemo(tester);

    final panel = tester.getRect(find.byKey(const ValueKey('account-panel')));
    final buttons = [
      for (final key in ['account-mute', 'account-deafen', 'account-settings'])
        tester.getRect(find.byKey(ValueKey(key))),
    ];
    for (final button in buttons) {
      expect(button.size, const Size.square(28));
      expect(button.center.dy, closeTo(panel.center.dy, 0.5));
    }
    expect(buttons.last.right, lessThanOrEqualTo(panel.right - 8));
    expect(buttons[0].right, lessThanOrEqualTo(buttons[1].left));
    expect(buttons[1].right, lessThanOrEqualTo(buttons[2].left));
  });

  testWidgets('mute and deafen act on the room and turn red', (tester) async {
    await openDemo(tester);
    await tap(tester, 'channel-forge-voice');
    await tap(tester, 'voice-channel-join');
    expect(iconColour(tester, 'account-mute'), isNot(danger));

    await tap(tester, 'account-mute');
    expect(find.byTooltip('Unmute'), findsWidgets);
    expect(iconColour(tester, 'account-mute'), danger);

    await tap(tester, 'account-deafen');
    expect(find.byTooltip('Undeafen'), findsWidgets);
    expect(iconColour(tester, 'account-deafen'), danger);
  });

  testWidgets('settings opens the settings window', (tester) async {
    await openDemo(tester);

    await tap(tester, 'account-settings');

    expect(find.byType(UserSettingsDialog), findsOneWidget);
  });
}
