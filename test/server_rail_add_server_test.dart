import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/presentation/widgets/server_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spaces = [
    CommunitySpace(
      id: 'forge',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
    CommunitySpace(
      id: 'night',
      name: 'Night Shift',
      monogram: 'NS',
      colorValue: 0xff765341,
    ),
  ];

  testWidgets(
    'the add-server entry is the green plus at the foot of the list',
    (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: ServerRail(
            spaces: spaces,
            activity: const {},
            selectedSpaceId: 'forge',
            onSelectSpace: (_) {},
            onToggleTheme: () {},
            onOpenConnections: () {},
            onAddServer: () => pressed++,
            sessionMode: SessionMode.demo,
            isDark: true,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('add-server')));
      expect(pressed, 1);
    },
  );

  testWidgets('without the server-access plane the rail hides the plus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: ServerRail(
          spaces: spaces,
          activity: const {},
          selectedSpaceId: 'forge',
          onSelectSpace: (_) {},
          onToggleTheme: () {},
          onOpenConnections: () {},
          sessionMode: SessionMode.demo,
          isDark: true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('add-server')), findsNothing);
  });
}
