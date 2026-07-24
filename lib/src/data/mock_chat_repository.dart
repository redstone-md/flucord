import 'dart:async';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import '../domain/forum_repository.dart';
import '../domain/message_forward_repository.dart';
import '../domain/message_flag_repository.dart';
import '../domain/poll_repository.dart';
import '../domain/reaction_repository.dart';
import '../domain/scheduled_event_repository.dart';
import '../domain/sticker_repository.dart';
import '../domain/thread_repository.dart';
import '../domain/voice_message_recorder.dart';
import '../domain/voice_message_repository.dart';
import 'mock_chat_seed.dart';

part 'mock_chat_repository_mutations.dart';
part 'mock_chat_repository_polls.dart';
part 'mock_chat_repository_reactions.dart';
part 'mock_chat_repository_forwards.dart';
part 'mock_chat_repository_message_flags.dart';
part 'mock_chat_repository_stickers.dart';
part 'mock_chat_repository_voice_messages.dart';
part 'mock_chat_repository_scheduled_events.dart';
part 'mock_chat_repository_direct_messages.dart';

final class MockChatRepository
    with
        _MockChatRepositoryPolls,
        _MockChatRepositoryReactions,
        _MockChatRepositoryForwards,
        _MockChatRepositoryMessageFlags,
        _MockChatRepositoryStickers,
        _MockChatRepositoryVoiceMessages,
        _MockChatRepositoryScheduledEvents,
        _MockChatRepositoryDirectMessages
    implements
        ChatRepository,
        ArchivedThreadRepository,
        ForumPostRepository,
        PollRepository,
        ReactionRepository,
        MessageForwardRepository,
        MessageFlagRepository,
        ScheduledEventRepository,
        StickerRepository,
        VoiceMessageRepository {
  MockChatRepository({this.latency = const Duration(milliseconds: 240)})
    : _workspace = MockChatSeed.withSystemMessages(
        MockChatSeed.withForums(_seedWorkspace()),
      );

  final Duration latency;
  @override
  ChatWorkspace _workspace;
  @override
  int _messageSequence = 100;
  @override
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  Future<ChatWorkspace> loadWorkspace() async {
    await _wait();
    _events.add(
      const RepositoryStatusChangedEvent(RepositoryConnectionStatus.connected),
    );
    return _workspace;
  }

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) async {
    await _wait();
    final messages = _workspace.messagesFor(channelId);
    final end = beforeMessageId == null
        ? messages.length
        : messages.indexWhere((message) => message.id == beforeMessageId);
    final safeEnd = end < 0 ? 0 : end;
    final start = safeEnd > 100 ? safeEnd - 100 : 0;
    return ChannelHistoryPage(
      history: ChannelHistory(
        channelId: channelId,
        messages: messages.sublist(start, safeEnd),
        members: _workspace.members,
      ),
      hasMore: start > 0,
    );
  }

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) async {
    await _wait();
    return ChannelHistory(
      channelId: channelId,
      messages: _workspace
          .messagesFor(channelId)
          .where((message) => message.isPinned)
          .toList(),
      members: _workspace.members,
    );
  }

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => _createMessageThread(
    channelId: channelId,
    messageId: messageId,
    name: name,
  );

  @override
  Future<ArchivedThreadPage> loadArchivedThreads(
    String parentChannelId, {
    DateTime? before,
  }) => _loadArchivedThreadPage(parentChannelId, before: before);

  @override
  Future<CreatedForumPost> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    List<PendingAttachment> attachments = const [],
    List<String> appliedTagIds = const [],
  }) => _createForumPost(
    channelId: channelId,
    name: name,
    content: content,
    autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    attachments: attachments,
    appliedTagIds: appliedTagIds,
  );

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) async {
    await _wait();
    final message = ChatMessage(
      id: 'local-${_messageSequence++}',
      channelId: channelId,
      authorId: authorId,
      body: body.trim(),
      sentAt: DateTime.now(),
      attachments: [
        for (var index = 0; index < attachments.length; index++)
          MessageAttachment(
            id: 'local-attachment-$index',
            fileName: attachments[index].name,
            url: attachments[index].path,
            size: attachments[index].size,
          ),
      ],
      reply: _replyFor(replyToMessageId),
      flags: suppressNotifications
          ? DiscordMessageFlag.suppressNotifications.bit
          : 0,
    );
    _workspace = _workspace.copyWith(
      messages: [..._workspace.messages, message],
    );
    return message;
  }

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) async {
    await _wait();
    final current = _workspace.messages.firstWhere(
      (message) => message.id == messageId && message.channelId == channelId,
    );
    final edited = current.copyWith(body: body.trim(), isEdited: true);
    _workspace = _workspace.upsertMessage(edited);
    _events.add(MessageUpsertedEvent(message: edited));
    return edited;
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _wait();
    _workspace = _workspace.removeMessage(messageId);
    _events.add(
      MessageDeletedEvent(messageId: messageId, channelId: channelId),
    );
  }

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _setReaction(messageId, emoji, add: true);

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _setReaction(messageId, emoji, add: false);

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _setPinned(messageId, true);

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) => _setPinned(messageId, false);

  @override
  Future<void> startTyping(String channelId) async {}

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) async {
    _workspace = _workspace.updateChannel(channel.id, (_) => channel);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> _wait() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
  }

  static ChatWorkspace _seedWorkspace() {
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
        body:
            'Release runner, cache migration, and reconnect checks are green.',
        sentAt: now.subtract(const Duration(minutes: 6)),
      ),
    ];
    return MockChatSeed.workspace(
      channels: channels,
      members: members,
      messages: messages,
    );
  }
}
