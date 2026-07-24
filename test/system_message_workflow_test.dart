import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('renders mock Discord system messages in the native timeline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FlucordApp());
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Omar N. joined the server.'), findsOneWidget);
    expect(find.text('Jack pinned a message to this channel.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('system-message-action-forge-pin-system')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
