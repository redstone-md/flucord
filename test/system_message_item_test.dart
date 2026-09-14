import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/system_message_item.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders system copy and routes pin and thread actions', (
    tester,
  ) async {
    String? jumpedMessageId;
    String? selectedChannelId;
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              SystemMessageItem(
                message: _message(
                  id: 'pin',
                  type: DiscordMessageType.channelPinnedMessage,
                  reference: const MessageReference(messageId: 'target-1'),
                ),
                member: _member,
                workspace: _workspace,
                onJumpToMessage: (id) => jumpedMessageId = id,
                onSelectChannel: (id) => selectedChannelId = id,
              ),
              SystemMessageItem(
                message: _message(
                  id: 'thread',
                  type: DiscordMessageType.threadCreated,
                  body: 'release-checklist',
                  reference: const MessageReference(channelId: 'thread-1'),
                ),
                member: _member,
                workspace: _workspace,
                onJumpToMessage: (id) => jumpedMessageId = id,
                onSelectChannel: (id) => selectedChannelId = id,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Jack pinned a message to this channel.'), findsOneWidget);
    expect(
      find.text('Jack started a thread: release-checklist'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('system-message-action-pin')));
    expect(jumpedMessageId, 'target-1');
    await tester.tap(
      find.byKey(const ValueKey('system-message-action-thread')),
    );
    expect(selectedChannelId, 'thread-1');
    expect(tester.takeException(), isNull);
  });
}

ChatMessage _message({
  required String id,
  required DiscordMessageType type,
  String body = '',
  MessageReference? reference,
}) => ChatMessage(
  id: id,
  channelId: 'channel-1',
  authorId: _member.id,
  body: body,
  sentAt: DateTime(2026, 7, 24, 8),
  type: type,
  reference: reference,
);

const _member = Member(
  id: 'user-1',
  displayName: 'Jack',
  initials: 'J',
  role: 'Operator',
  presence: Presence.online,
  colorValue: 0xff5865f2,
);

final _workspace = ChatWorkspace(
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
    ConversationChannel(
      id: 'thread-1',
      spaceId: 'guild-1',
      name: 'release-checklist',
      topic: '',
      kind: ChannelKind.text,
      parentId: 'channel-1',
      isThread: true,
    ),
  ],
  members: const [_member],
  messages: const [],
  currentMemberId: 'user-1',
);
