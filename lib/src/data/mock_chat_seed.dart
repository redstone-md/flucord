import '../domain/chat_models.dart';

final class MockChatSeed {
  const MockChatSeed._();

  static const spaces = [
    CommunitySpace(
      id: 'forge',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
    CommunitySpace(
      id: 'night',
      name: 'Night Shift',
      monogram: 'NS',
      colorValue: 0xff765341,
    ),
    CommunitySpace(
      id: 'studio',
      name: 'Signal Studio',
      monogram: 'SS',
      colorValue: 0xff5f5b76,
    ),
    CommunitySpace(
      id: 'lab',
      name: 'Home Lab',
      monogram: 'HL',
      colorValue: 0xff59636a,
    ),
  ];

  static const categories = [
    ChannelCategory(
      id: 'forge-project',
      spaceId: 'forge',
      name: 'The Forge',
      position: 0,
    ),
  ];

  static const emojis = [
    GuildEmoji(id: 'forge-spark', spaceId: 'forge', name: 'forge_spark'),
    GuildEmoji(id: 'ship-green', spaceId: 'forge', name: 'ship_green'),
  ];

  static final stickers = [
    GuildSticker(
      item: const MessageSticker(
        id: 'forge-signal',
        name: 'Native signal',
        format: StickerFormat.png,
        url: 'https://cdn.discordapp.com/stickers/forge-signal.png',
      ),
      spaceId: 'forge',
      tags: const ['signal', 'native'],
      available: true,
    ),
    GuildSticker(
      item: const MessageSticker(
        id: 'forge-relay',
        name: 'Relay click',
        format: StickerFormat.lottie,
        url: 'https://cdn.discordapp.com/stickers/forge-relay.json',
      ),
      spaceId: 'forge',
      tags: const ['relay', 'deploy'],
      available: true,
    ),
  ];

  static ChatMessage inboxMention(DateTime now) => ChatMessage(
    id: 'design-mention',
    channelId: 'forge-design',
    authorId: 'mira',
    body: '<@jack> the Inbox path now lands on this exact review note.',
    sentAt: now.subtract(const Duration(hours: 1, minutes: 42)),
    mentionsCurrentMember: true,
  );

  static ChatWorkspace workspace({
    required List<ConversationChannel> channels,
    required List<Member> members,
    required List<ChatMessage> messages,
  }) => ChatWorkspace(
    spaces: spaces,
    categories: categories,
    emojis: emojis,
    stickers: stickers,
    channels: channels,
    members: members,
    messages: messages,
    currentMemberId: 'jack',
  );

  static ChatWorkspace withForums(ChatWorkspace workspace) {
    const forum = ConversationChannel(
      id: 'forge-forum',
      spaceId: 'forge',
      name: 'field-reports',
      topic: 'Post implementation reports and attach a subsystem tag.',
      kind: ChannelKind.forum,
      position: 4,
      parentId: 'forge-project',
      availableTags: [
        ForumTag(id: 'tag-client', name: 'Client', moderated: false),
        ForumTag(id: 'tag-transport', name: 'Transport', moderated: false),
      ],
      defaultAutoArchiveDurationMinutes: 1440,
      defaultSortOrder: ForumSortOrder.latestActivity,
      defaultForumLayout: ForumLayout.listView,
    );
    const post = ConversationChannel(
      id: 'forge-forum-bootstrap',
      spaceId: 'forge',
      name: 'bootstrap-report',
      topic: '',
      kind: ChannelKind.text,
      parentId: 'forge-forum',
      isThread: true,
      appliedTagIds: ['tag-client'],
      autoArchiveDurationMinutes: 1440,
    );
    final message = ChatMessage(
      id: 'forge-forum-bootstrap-starter',
      channelId: post.id,
      authorId: 'fly',
      body: 'Native bootstrap and cache restore are stable.',
      sentAt: DateTime.now().subtract(const Duration(hours: 4)),
    );
    return workspace.copyWith(
      channels: [...workspace.channels, forum, post],
      messages: [...workspace.messages, message],
    );
  }

  static ChatWorkspace withSystemMessages(ChatWorkspace workspace) {
    final now = DateTime.now();
    final messages = [
      ...workspace.messages,
      ChatMessage(
        id: 'forge-join-system',
        channelId: 'forge-general',
        authorId: 'omar',
        body: '',
        sentAt: now.subtract(const Duration(minutes: 52)),
        type: DiscordMessageType.userJoin,
      ),
      ChatMessage(
        id: 'forge-pin-system',
        channelId: 'forge-general',
        authorId: 'jack',
        body: '',
        sentAt: now.subtract(const Duration(minutes: 17)),
        type: DiscordMessageType.channelPinnedMessage,
        reference: const MessageReference(
          messageId: 'm4',
          channelId: 'forge-general',
        ),
      ),
      ChatMessage(
        id: 'forge-thread-system',
        channelId: 'forge-native',
        authorId: 'roman',
        body: 'release-checklist',
        sentAt: now.subtract(const Duration(minutes: 7)),
        type: DiscordMessageType.threadCreated,
        reference: const MessageReference(channelId: 'forge-thread-release'),
      ),
    ]..sort((left, right) => left.sentAt.compareTo(right.sentAt));
    return workspace.copyWith(messages: messages);
  }
}
