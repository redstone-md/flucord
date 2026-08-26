import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/presentation/widgets/message_list.dart';

void main() {
  testWidgets('renders mock Discord system messages in the native timeline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // The channel opens on its newest message, so the older system messages
    // are reached by scrolling back through the conversation.
    expect(find.text('Jack pinned a message to this channel.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('system-message-action-forge-pin-system')),
      findsOneWidget,
    );

    final timeline = find.descendant(
      of: find.byType(MessageList),
      matching: find.byType(Scrollable),
    );
    await tester.drag(timeline, const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(find.text('Omar N. joined the server.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
