import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/inbox_catalog.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('projects unread channels and exact mention messages', () {
    final catalog = InboxCatalog.fromWorkspace(_workspace());

    expect(catalog.summary.unreadChannelCount, 3);
    expect(catalog.summary.mentionCount, 2);
    expect(catalog.summary.hasActivity, isTrue);
    expect(catalog.unread.map((entry) => entry.target.channelId), [
      'design',
      'general',
      'voice',
    ]);
    expect(catalog.unread.first.path, 'The Forge / #design');
    expect(catalog.unread.first.mentionCount, 2);
    expect(catalog.unread[1].firstUnreadMessageId, 'message-1');
    expect(catalog.unread.last.path, 'The Forge / voice');

    final mention = catalog.mentions.single;
    expect(mention.target.channelId, 'design');
    expect(mention.target.messageId, 'mention-1');
    expect(mention.path, 'The Forge / #design');
    expect(mention.author.displayName, 'Mira');
    expect(mention.message.body, 'Jack, review the native inbox.');
  });

  test('keeps mention history after counters clear and applies the cap', () {
    final workspace = _workspace().copyWith(
      channels: [
        for (final channel in _workspace().channels) channel.markRead(),
      ],
      messages: [
        ..._workspace().messages,
        ChatMessage(
          id: 'mention-2',
          channelId: 'general',
          authorId: 'mira',
          body: 'Second mention',
          sentAt: DateTime.utc(2026, 7, 23, 3),
          mentionsCurrentMember: true,
        ),
      ],
    );

    final catalog = InboxCatalog.fromWorkspace(workspace, maxMentions: 1);

    expect(catalog.summary.hasActivity, isFalse);
    expect(catalog.unread, isEmpty);
    expect(catalog.mentions.single.message.id, 'mention-2');
  });

  test('ignores orphaned authors and clamps a negative mention cap', () {
    final workspace = _workspace().copyWith(
      messages: [
        ..._workspace().messages,
        ChatMessage(
          id: 'orphaned-mention',
          channelId: 'design',
          authorId: 'missing-member',
          body: 'Cached before its author.',
          sentAt: DateTime.utc(2026, 7, 23, 4),
          mentionsCurrentMember: true,
        ),
      ],
    );

    final catalog = InboxCatalog.fromWorkspace(workspace, maxMentions: -1);

    expect(catalog.summary.mentionCount, 2);
    expect(catalog.mentions, isEmpty);
  });
}

ChatWorkspace _workspace() => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'forge',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'general',
      spaceId: 'forge',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      unread: true,
      firstUnreadMessageId: 'message-1',
    ),
    ConversationChannel(
      id: 'design',
      spaceId: 'forge',
      name: 'design',
      topic: '',
      kind: ChannelKind.text,
      mentionCount: 2,
    ),
    ConversationChannel(
      id: 'voice',
      spaceId: 'forge',
      name: 'voice',
      topic: '',
      kind: ChannelKind.voice,
      unread: true,
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
      id: 'message-1',
      channelId: 'general',
      authorId: 'mira',
      body: 'Unread work.',
      sentAt: DateTime.utc(2026, 7, 23, 1),
    ),
    ChatMessage(
      id: 'mention-1',
      channelId: 'design',
      authorId: 'mira',
      body: 'Jack, review the native inbox.',
      sentAt: DateTime.utc(2026, 7, 23, 2),
      mentionsCurrentMember: true,
    ),
  ],
  currentMemberId: 'jack',
);
