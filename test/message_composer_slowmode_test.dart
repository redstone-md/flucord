import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('a channel without slowmode shows no countdown', (tester) async {
    await _pump(tester, slowmode: Duration.zero, slowmodeUntil: null);

    expect(
      find.byKey(const ValueKey('composer-slowmode-countdown')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('slowmode holding the account shows a counting note', (
    tester,
  ) async {
    await _pump(
      tester,
      slowmode: const Duration(seconds: 30),
      slowmodeUntil: DateTime.now().add(const Duration(seconds: 12)),
    );

    final note = find.byKey(const ValueKey('composer-slowmode-countdown'));
    expect(note, findsOneWidget);
    expect(find.textContaining('Wait '), findsOneWidget);
    // The countdown ticks: a second later the note still names a wait.
    await tester.pump(const Duration(seconds: 2));
    expect(note, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slowmode that already elapsed shows nothing', (tester) async {
    await _pump(
      tester,
      slowmode: const Duration(seconds: 30),
      slowmodeUntil: DateTime.now().subtract(const Duration(seconds: 5)),
    );

    expect(
      find.byKey(const ValueKey('composer-slowmode-countdown')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Duration slowmode,
  required DateTime? slowmodeUntil,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: MessageComposer(
          channelId: 'general',
          channelName: 'general',
          spaceName: 'The Forge',
          emojiSections: const [],
          stickerSections: const [],
          isSending: false,
          slowmode: slowmode,
          slowmodeUntil: slowmodeUntil,
          onSend: (_, _, _, _) async => true,
          onCreatePoll: (_) async => true,
          onSendStickers: (_) async => true,
          onCancelReply: () {},
          onTyping: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
