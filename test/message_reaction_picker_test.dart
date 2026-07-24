import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('uses the anchored picker and opens reaction details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    String? selectedReaction;
    var detailLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 680,
              child: MessageItem(
                key: const ValueKey('reaction-message'),
                message: _message,
                member: _member,
                workspace: _workspace,
                grouped: false,
                isCurrentUser: false,
                onReply: (_) {},
                onEdit: (_, _) async => true,
                onDelete: (_) async {},
                onToggleReaction: (_, _) async {},
                onLoadReactionUsers: (_, _, _, _) async {
                  detailLoads++;
                  return const ReactionUsersPage(
                    users: [_member],
                    hasMore: false,
                  );
                },
                onAddReaction: (_, emoji) async {
                  selectedReaction = emoji;
                },
                onCreateThread: (_, _, _) async => true,
                onTogglePin: (_) async {},
                onEndPoll: (_) async => true,
                onForward: (_, _) async => true,
                linkLauncher: const _TestLinkLauncher(),
                onSelectChannel: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('reaction-custom-message-1-emoji-1')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('forge_spark reaction, 2'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('reaction-message'))),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('add-reaction-message-1')));
    await tester.pumpAndSettle();
    expect(find.text('Add reaction'), findsOneWidget);

    final picker = find.byKey(const ValueKey('emoji-picker'));
    await mouse.moveTo(tester.getCenter(picker));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('add-reaction-message-1')),
      findsOneWidget,
    );

    final pickerRect = tester.getRect(picker);
    expect(pickerRect.left, greaterThanOrEqualTo(0));
    expect(pickerRect.top, greaterThanOrEqualTo(0));
    expect(pickerRect.right, lessThanOrEqualTo(800));
    expect(pickerRect.bottom, lessThanOrEqualTo(700));

    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'forge spark',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('emoji-choice-custom-emoji-1')));
    await tester.pumpAndSettle();

    expect(selectedReaction, 'forge_spark:emoji-1');
    expect(picker, findsNothing);

    selectedReaction = null;
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('reaction-message'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-reaction-message-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'rocket',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('emoji-choice-unicode-rocket')));
    await tester.pumpAndSettle();

    expect(selectedReaction, '🚀');

    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('reaction-message'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('view-reactions-message-1')));
    await tester.pumpAndSettle();
    expect(find.text('Reactions'), findsOneWidget);
    expect(detailLoads, 1);
    semantics.dispose();
  });
}

final _workspace = ChatWorkspace(
  spaces: [
    CommunitySpace(
      id: 'space-1',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: [
    ConversationChannel(
      id: 'channel-1',
      spaceId: 'space-1',
      name: 'general',
      topic: 'General',
      kind: ChannelKind.text,
    ),
  ],
  members: [_member],
  messages: [_message],
  emojis: [GuildEmoji(id: 'emoji-1', spaceId: 'space-1', name: 'forge_spark')],
  currentMemberId: 'current-user',
);

const _member = Member(
  id: 'member-1',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Design',
  presence: Presence.online,
  colorValue: 0xff665f82,
);

final _message = ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'Native reactions should use the complete guild catalog.',
  sentAt: DateTime(2026, 7, 23, 3, 47),
  reactions: const [
    MessageReaction(emojiName: 'forge_spark', emojiId: 'emoji-1', count: 2),
  ],
);

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}
