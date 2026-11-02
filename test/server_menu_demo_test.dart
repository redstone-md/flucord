import 'package:flucord/src/app.dart';
import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/presentation/widgets/server_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The demo transport holds none of what the server menu acts on: no read
/// state, no server management, no reports. Right-clicking a server there has
/// nothing to offer, so no menu opens.
void main() {
  testWidgets('right-clicking a server in the demo opens no empty menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      FlucordApp(
        bootstrap: AppBootstrap(
          initialRepository: MockChatRepository(),
          initialSessionMode: SessionMode.demo,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final mouse = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('space-forge'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PopupMenuItem<ServerMenuAction>), findsNothing);
  });
}
