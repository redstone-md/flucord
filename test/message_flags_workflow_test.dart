import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';

void main() {
  testWidgets('sends a silent message through the full native workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('send-silently')));
    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Silent native path confirmed.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final item = tester.widget<MessageItem>(
      find.ancestor(
        of: find.text('Silent native path confirmed.'),
        matching: find.byType(MessageItem),
      ),
    );
    expect(item.message.suppressesNotifications, isTrue);
    expect(find.byTooltip('Send silently'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
