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
    channels: channels,
    members: members,
    messages: messages,
    currentMemberId: 'jack',
  );
}
