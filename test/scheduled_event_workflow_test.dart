import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('opens server events and navigates into its voice room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guild-events-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guild-events-button')));
    await tester.pumpAndSettle();
    expect(find.text('Native client review'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guild-event-forge-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guild-events-dialog')), findsNothing);
    // Opening a voice channel shows the room; joining it is a button, which
    // is what Discord does.
    await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
