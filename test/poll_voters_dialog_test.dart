import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/poll_repository.dart';
import 'package:flucord/src/presentation/widgets/poll_voters_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists the voters of each answer, a page at a time', (
    tester,
  ) async {
    final asked = <String>[];
    Future<MemberPage> load(
      ChatMessage message,
      PollAnswer answer,
      String? after,
    ) async {
      asked.add('${answer.id} after $after');
      return switch ((answer.id, after)) {
        (1, null) => MemberPage(
          users: [_member('a', 'Ada')],
          hasMore: true,
        ),
        (1, 'a') => MemberPage(users: [_member('b', 'Bo')], hasMore: false),
        _ => MemberPage(users: [_member('c', 'Cy')], hasMore: false),
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: PollVotersDialog(message: _pollMessage(), onLoad: load),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('poll-voters-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Bo'), findsOneWidget);
    expect(find.byKey(const ValueKey('poll-voters-load-more')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('poll-voters-answer-2')));
    await tester.pumpAndSettle();
    expect(find.text('Cy'), findsOneWidget);
    expect(find.text('Ada'), findsNothing);
    expect(asked, ['1 after null', '1 after a', '2 after null']);
  });
}

Member _member(String id, String name) => Member(
  id: id,
  displayName: name,
  initials: name[0],
  role: 'Voted',
  presence: Presence.offline,
  colorValue: 0xFF5865F2,
);

ChatMessage _pollMessage() => ChatMessage(
  id: 'poll-1',
  channelId: 'channel-1',
  authorId: 'author-1',
  body: '',
  sentAt: DateTime(2026, 7, 25),
  poll: MessagePoll(
    question: 'Which build ships?',
    answers: const [
      PollAnswer(id: 1, text: 'Stable', count: 2),
      PollAnswer(id: 2, text: 'Canary', count: 1),
    ],
    allowMultiselect: false,
    isFinalized: false,
  ),
);
