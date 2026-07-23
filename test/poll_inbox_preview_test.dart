import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/inbox_catalog.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/inbox_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('uses the poll question for a bodyless mention preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: InboxDialog(
            catalog: InboxCatalog.fromWorkspace(_workspace()),
            onMarkAllRead: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.textContaining('Mentions'));
    await tester.pumpAndSettle();

    expect(find.text('Which build ships?'), findsOneWidget);
    expect(find.text('Attachment or embed'), findsNothing);
  });
}

ChatWorkspace _workspace() => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'general',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      mentionCount: 1,
    ),
  ],
  members: const [
    Member(
      id: 'jack',
      displayName: 'Jack',
      initials: 'JK',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff48745f,
    ),
    Member(
      id: 'mira',
      displayName: 'Mira',
      initials: 'MI',
      role: 'Design',
      presence: Presence.online,
      colorValue: 0xff665f82,
    ),
  ],
  messages: [
    ChatMessage(
      id: 'poll-mention',
      channelId: 'general',
      authorId: 'mira',
      body: '',
      sentAt: DateTime.now(),
      mentionsCurrentMember: true,
      poll: MessagePoll(
        question: 'Which build ships?',
        answers: const [
          PollAnswer(id: 1, text: 'Stable', count: 2),
          PollAnswer(id: 2, text: 'Canary', count: 1),
        ],
        allowMultiselect: false,
        isFinalized: false,
      ),
    ),
  ],
  currentMemberId: 'jack',
);
