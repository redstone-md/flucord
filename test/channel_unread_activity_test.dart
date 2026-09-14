import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('retains the first message across one unread burst', () {
    final first = _workspace.markChannelUnread(
      'channel-1',
      messageId: 'message-10',
      mention: false,
    );
    final second = first.markChannelUnread(
      'channel-1',
      messageId: 'message-11',
      mention: true,
    );
    final unread = second.channelById('channel-1');

    expect(unread.unread, isTrue);
    expect(unread.mentionCount, 1);
    expect(unread.firstUnreadMessageId, 'message-10');

    final read = second.markChannelRead('channel-1');
    expect(read.channelById('channel-1').unread, isFalse);
    expect(read.channelById('channel-1').mentionCount, 0);
    expect(read.channelById('channel-1').firstUnreadMessageId, 'message-10');

    final dismissed = read.clearChannelUnreadBoundary('channel-1');
    expect(dismissed.channelById('channel-1').firstUnreadMessageId, isNull);
  });

  test(
    'preserves activity through remote channel updates and cached restore',
    () {
      final unread = _workspace.markChannelUnread(
        'channel-1',
        messageId: 'message-10',
        mention: true,
      );
      const remote = ConversationChannel(
        id: 'channel-1',
        spaceId: 'space-1',
        name: 'renamed',
        topic: 'Updated remotely',
        kind: ChannelKind.text,
      );

      final updated = unread.upsertChannel(remote).channelById('channel-1');
      expect(updated.name, 'renamed');
      expect(updated.unread, isTrue);
      expect(updated.firstUnreadMessageId, 'message-10');

      final restored = _workspace
          .upsertChannel(remote)
          .restoreChannelActivityFrom(unread)
          .channelById('channel-1');
      expect(restored.mentionCount, 1);
      expect(restored.firstUnreadMessageId, 'message-10');
    },
  );

  test('removing the boundary message clears only its marker', () {
    final unread = _workspace.markChannelUnread(
      'channel-1',
      messageId: 'message-10',
      mention: false,
    );

    final updated = unread.removeMessage('message-10');
    expect(updated.channelById('channel-1').unread, isTrue);
    expect(updated.channelById('channel-1').firstUnreadMessageId, isNull);
  });
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'space-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'channel-1',
      spaceId: 'space-1',
      name: 'general',
      topic: 'Core work',
      kind: ChannelKind.text,
    ),
  ],
  members: const [
    Member(
      id: 'bot-1',
      displayName: 'Flucord',
      initials: 'FL',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  messages: [
    ChatMessage(
      id: 'message-10',
      channelId: 'channel-1',
      authorId: 'bot-1',
      body: 'First unread',
      sentAt: DateTime.utc(2026, 7, 23),
    ),
  ],
  currentMemberId: 'bot-1',
);
