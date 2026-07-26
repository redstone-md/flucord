part of 'mock_chat_repository.dart';

/// The demo workspace the offline repository starts from. It lives in its own
/// part because it is data, not behaviour, and it would otherwise crowd the
/// repository it seeds past the file-size budget.
ChatWorkspace _seedWorkspace() {
  const channels = [
    ConversationChannel(
      id: 'forge-general',
      spaceId: 'forge',
      name: 'general',
      topic: 'Build notes, decisions, and the work in front of us.',
      kind: ChannelKind.text,
      position: 0,
      parentId: 'forge-project',
      unread: true,
      firstUnreadMessageId: 'm3',
    ),
    ConversationChannel(
      id: 'forge-design',
      spaceId: 'forge',
      name: 'design',
      topic: 'Interface details, references, and review.',
      kind: ChannelKind.text,
      position: 1,
      parentId: 'forge-project',
      mentionCount: 2,
    ),
    ConversationChannel(
      id: 'forge-native',
      spaceId: 'forge',
      name: 'native-client',
      topic: 'Flutter desktop architecture and platform integration.',
      kind: ChannelKind.text,
      position: 2,
      parentId: 'forge-project',
    ),
    ConversationChannel(
      id: 'forge-thread-release',
      spaceId: 'forge',
      name: 'release-checklist',
      topic: 'Active thread under native-client.',
      kind: ChannelKind.text,
      parentId: 'forge-native',
      isThread: true,
    ),
    ConversationChannel(
      id: 'forge-voice',
      spaceId: 'forge',
      name: 'workbench',
      topic: 'Open voice room',
      kind: ChannelKind.voice,
      position: 3,
      parentId: 'forge-project',
    ),
    ConversationChannel(
      id: 'night-ops',
      spaceId: 'night',
      name: 'operations',
      topic: 'Late deployments and incident notes.',
      kind: ChannelKind.text,
      unread: true,
    ),
    ConversationChannel(
      id: 'night-radio',
      spaceId: 'night',
      name: 'radio-room',
      topic: 'Open voice room',
      kind: ChannelKind.voice,
    ),
    ConversationChannel(
      id: 'studio-feedback',
      spaceId: 'studio',
      name: 'feedback',
      topic: 'Cuts, mixes, and focused critique.',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: 'lab-rack',
      spaceId: 'lab',
      name: 'server-rack',
      topic: 'Machines that refuse to die.',
      kind: ChannelKind.text,
    ),
  ];
  const members = [
    Member(
      id: 'jack',
      displayName: 'Jack',
      initials: 'JK',
      role: 'Architect',
      presence: Presence.online,
      colorValue: 0xff48745f,
    ),
    Member(
      id: 'fly',
      displayName: 'Fly',
      initials: 'FL',
      role: 'Native systems',
      presence: Presence.online,
      colorValue: 0xff835c45,
    ),
    Member(
      id: 'mira',
      displayName: 'Mira Chen',
      initials: 'MC',
      role: 'Product design',
      presence: Presence.online,
      colorValue: 0xff665f82,
    ),
    Member(
      id: 'roman',
      displayName: 'Roman Vale',
      initials: 'RV',
      role: 'Infrastructure',
      presence: Presence.idle,
      colorValue: 0xff506674,
    ),
    Member(
      id: 'lena',
      displayName: 'Lena Ortiz',
      initials: 'LO',
      role: 'Audio systems',
      presence: Presence.offline,
      colorValue: 0xff715b64,
    ),
    Member(
      id: 'omar',
      displayName: 'Omar N.',
      initials: 'ON',
      role: 'Quality',
      presence: Presence.offline,
      colorValue: 0xff5d6252,
    ),
  ];
  final now = DateTime.now();
  final messages = [
    ChatMessage(
      id: 'm1',
      channelId: 'forge-general',
      authorId: 'mira',
      body:
          'The navigation pass is ready. I kept hierarchy in the type and borders, not floating panels.',
      sentAt: now.subtract(const Duration(minutes: 44)),
    ),
    ChatMessage(
      id: 'm2',
      channelId: 'forge-general',
      authorId: 'roman',
      body:
          'Windows runner is clean. Cold start is under a second on the test machine.',
      sentAt: now.subtract(const Duration(minutes: 38)),
    ),
    ChatMessage(
      id: 'm3',
      channelId: 'forge-general',
      authorId: 'fly',
      body:
          'Good. Next tracer bullet is channel switching plus local send. Transport stays behind the repository boundary.',
      sentAt: now.subtract(const Duration(minutes: 31)),
      attachments: const [
        MessageAttachment(
          id: 'a1',
          fileName: 'transport-boundary.md',
          url: 'local://transport-boundary.md',
          size: 18420,
          contentType: 'text/markdown',
        ),
      ],
    ),
    ChatMessage(
      id: 'm4',
      channelId: 'forge-general',
      authorId: 'jack',
      body:
          'Ship the vertical slice first. We can make it loud after it is real.',
      sentAt: now.subtract(const Duration(minutes: 18)),
      reply: const MessageReply(
        messageId: 'm3',
        authorId: 'fly',
        body: 'Next tracer bullet is channel switching plus local send.',
      ),
      reactions: const [
        MessageReaction(emojiName: '✓', count: 3, reactedByCurrentUser: true),
        MessageReaction(emojiName: '🔥', count: 2),
      ],
      isPinned: true,
    ),
    ChatMessage(
      id: 'm5',
      channelId: 'forge-design',
      authorId: 'mira',
      body:
          'The selected path should read as one continuous signal from server to channel to conversation.',
      sentAt: now.subtract(const Duration(hours: 2, minutes: 12)),
    ),
    ChatMessage(
      id: 'm6',
      channelId: 'forge-design',
      authorId: 'fly',
      body:
          'Agreed. One green accent, copper only for warnings. Everything else stays graphite.',
      sentAt: now.subtract(const Duration(hours: 1, minutes: 56)),
    ),
    MockChatSeed.inboxMention(now),
    ChatMessage(
      id: 'm7',
      channelId: 'forge-native',
      authorId: 'roman',
      body:
          'Repository contract is small enough to replace with WebSocket plus SQLite without touching presentation.',
      sentAt: now.subtract(const Duration(hours: 3, minutes: 8)),
    ),
    ChatMessage(
      id: 'm8',
      channelId: 'night-ops',
      authorId: 'roman',
      body:
          'Old rack node recovered. Relay clicked twice, then all checks went green.',
      sentAt: now.subtract(const Duration(minutes: 9)),
    ),
    ChatMessage(
      id: 'm9',
      channelId: 'studio-feedback',
      authorId: 'lena',
      body:
          'Uploaded the dry voice sample. No suppression or gate, so we have a useful baseline.',
      sentAt: now.subtract(const Duration(hours: 5)),
    ),
    ChatMessage(
      id: 'm10',
      channelId: 'lab-rack',
      authorId: 'jack',
      body: 'The old server is still alive. Leave the fan curve alone.',
      sentAt: now.subtract(const Duration(days: 1, minutes: 27)),
    ),
    ChatMessage(
      id: 'm11',
      channelId: 'forge-thread-release',
      authorId: 'roman',
      body: 'Release runner, cache migration, and reconnect checks are green.',
      sentAt: now.subtract(const Duration(minutes: 6)),
    ),
    ChatMessage(
      id: 'm12',
      channelId: 'forge-voice',
      authorId: 'lena',
      body: 'Bench notes live here while the room is open.',
      sentAt: now.subtract(const Duration(minutes: 24)),
    ),
    ChatMessage(
      id: 'm13',
      channelId: 'forge-voice',
      authorId: 'roman',
      body: 'Capture settings are two clicks off the room toolbar.',
      sentAt: now.subtract(const Duration(minutes: 21)),
    ),
    ChatMessage(
      id: 'm14',
      channelId: 'forge-native',
      authorId: 'lena',
      body: 'Bench transcript stays in <#forge-voice> until we cut a report.',
      sentAt: now.subtract(const Duration(minutes: 12)),
    ),
  ];
  return MockChatSeed.workspace(
    channels: channels,
    members: members,
    messages: messages,
  );
}
