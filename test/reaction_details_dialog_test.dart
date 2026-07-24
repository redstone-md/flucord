import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/presentation/widgets/reaction_details_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('separates normal and super reactors and switches emoji', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final message = _message();

    await tester.pumpWidget(
      _host(
        message,
        onLoad: (_, reaction, type, _) async {
          if (reaction.emojiName == '🔥') {
            return ReactionUsersPage(
              users: type == DiscordReactionType.normal
                  ? const [_jack]
                  : const [_omar],
              hasMore: false,
            );
          }
          return const ReactionUsersPage(users: [_roman], hasMore: false);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 normal'), findsOneWidget);
    expect(find.text('1 super'), findsOneWidget);
    expect(find.text('Jack'), findsOneWidget);
    expect(find.text('Omar'), findsOneWidget);
    expect(find.text('Super'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reaction-detail-tab-✅')));
    await tester.pumpAndSettle();

    expect(find.text('1 normal'), findsOneWidget);
    expect(find.text('Roman'), findsOneWidget);
    expect(find.text('Jack'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retains loaded reactors while retrying the next page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var calls = 0;

    await tester.pumpWidget(
      _host(
        _message(),
        onLoad: (_, _, type, after) async {
          if (type == DiscordReactionType.burst) {
            return const ReactionUsersPage(users: [_omar], hasMore: false);
          }
          calls++;
          if (after == null) {
            return const ReactionUsersPage(users: [_jack], hasMore: true);
          }
          if (calls == 2) throw StateError('temporary failure');
          return const ReactionUsersPage(users: [_roman], hasMore: false);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Jack'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reaction-details-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Could not load reactions'), findsOneWidget);
    expect(find.text('Jack'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Roman'), findsOneWidget);
    expect(find.text('Could not load reactions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the reaction ledger usable at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(
        _message(),
        onLoad: (_, _, type, _) async => ReactionUsersPage(
          users: type == DiscordReactionType.normal
              ? const [_jack, _roman]
              : const [_omar],
          hasMore: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reactions'), findsOneWidget);
    expect(find.text('Jack'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(ChatMessage message, {required ReactionUsersLoader onLoad}) =>
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ReactionDetailsDialog(
          message: message,
          workspace: _workspace(message),
          initialReaction: message.reactions.first,
          onLoad: onLoad,
        ),
      ),
    );

ChatMessage _message() => ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: _jack.id,
  body: 'Ship it',
  sentAt: DateTime(2026, 7, 24, 8),
  reactions: const [
    MessageReaction(
      emojiName: '🔥',
      count: 3,
      normalCount: 2,
      burstCount: 1,
      burstColorValues: [0xffff3366],
    ),
    MessageReaction(emojiName: '✅', count: 1),
  ],
);

ChatWorkspace _workspace(ChatMessage message) => ChatWorkspace(
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
      id: 'channel-1',
      spaceId: 'guild-1',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [_jack, _omar, _roman],
  messages: [message],
  currentMemberId: _jack.id,
);

const _jack = Member(
  id: 'user-1',
  displayName: 'Jack',
  initials: 'J',
  role: 'Operator',
  presence: Presence.online,
  colorValue: 0xff5865f2,
);

const _omar = Member(
  id: 'user-2',
  displayName: 'Omar',
  initials: 'O',
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff23a55a,
);

const _roman = Member(
  id: 'user-3',
  displayName: 'Roman',
  initials: 'R',
  role: 'Member',
  presence: Presence.offline,
  colorValue: 0xff80848e,
);
