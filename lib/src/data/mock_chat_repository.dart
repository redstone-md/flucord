import 'dart:async';
import '../domain/application_command.dart';
import '../domain/gif_picker.dart';
import '../domain/soundboard.dart';
import '../domain/stage_channel.dart';
import '../domain/thread_membership.dart';
import '../domain/user_profile.dart';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import '../domain/forum_repository.dart';
import '../domain/guild_management_repository.dart';
import '../domain/message_forward_repository.dart';
import '../domain/moderation_repository.dart';
import '../domain/message_flag_repository.dart';
import '../domain/message_search_repository.dart';
import '../domain/poll_repository.dart';
import '../domain/presence_repository.dart';
import '../domain/reaction_repository.dart';
import '../domain/scheduled_event_repository.dart';
import '../domain/sticker_repository.dart';
import '../domain/thread_repository.dart';
import '../domain/read_state_repository.dart';
import '../domain/user_settings_repository.dart';
import '../domain/voice_call.dart';
import '../domain/voice_connection.dart';
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
part 'mock_chat_repository_seed.dart';

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

  /// The demo workspace has no socket behind it, so there is nothing to join
  /// and nobody to ring.
  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserProfileRepository? get userProfile => null;

  @override
  ThreadMembershipRepository? get threadMembership => null;

  @override
  StageRepository? get stages => null;

  @override
  SoundboardRepository? get soundboard => null;

  @override
  GifRepository? get gifs => null;

  @override
  ApplicationCommandRepository? get applicationCommands => null;

  /// There is no Discord account behind the demo data, so there is no settings
  /// blob to read and nowhere for a change to be saved.
  @override
  UserSettingsRepository? get userSettings => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  DirectCallService? get directCalls => null;

  /// The demo workspace is the whole corpus and it is already loaded,
  /// so there is no server to ask for the messages it does not hold.
  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  GuildManagementRepository? get guildManagement => null;

  @override
  ModerationRepository? get moderation => null;

  /// Nothing is signed in, so there is no account whose status could be
  /// broadcast and no socket that could carry it.
  @override
  PresenceService? get presence => null;

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
}
