import 'dart:async';
import '../../domain/thread_membership.dart';
import '../../domain/user_profile.dart';

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/forum_repository.dart';
import '../../domain/guild_management_repository.dart';
import '../../domain/message_forward_repository.dart';
import '../../domain/moderation_repository.dart';
import '../../domain/message_flag_repository.dart';
import '../../domain/message_search_repository.dart';
import '../../domain/poll_repository.dart';
import '../../domain/presence_repository.dart';
import '../../domain/reaction_repository.dart';
import '../../domain/scheduled_event_repository.dart';
import '../../domain/sticker_repository.dart';
import '../../domain/thread_repository.dart';
import '../../domain/read_state_repository.dart';
import '../../domain/user_settings_repository.dart';
import '../../domain/voice_call.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import '../../domain/voice_message_recorder.dart';
import '../../domain/voice_message_repository.dart';
import 'discord_api_client.dart';
import 'discord_channel_handler.dart';
import 'discord_direct_messages.dart';
import 'discord_gateway_client.dart';
import 'discord_guild_member_loader.dart';
import 'discord_history_loader.dart';
import 'discord_mapper.dart';
import 'discord_message_nonce_factory.dart';
import 'discord_presence_mapper.dart';
import 'discord_reaction_handler.dart';
import 'discord_poll_vote_handler.dart';
import 'discord_repository_events.dart';
import 'discord_voice_signaling_service.dart';

part 'discord_chat_repository_messages.dart';
part 'discord_chat_repository_emojis.dart';
part 'discord_chat_repository_threads.dart';
part 'discord_chat_repository_forums.dart';
part 'discord_chat_repository_pins.dart';
part 'discord_chat_repository_polls.dart';
part 'discord_chat_repository_reactions.dart';
part 'discord_chat_repository_forwards.dart';
part 'discord_chat_repository_stickers.dart';
part 'discord_chat_repository_voice_messages.dart';
part 'discord_chat_repository_scheduled_events.dart';
part 'discord_chat_repository_gateway.dart';

final class DiscordChatRepository
    with
        _DiscordChatRepositoryMessageMutations,
        _DiscordChatRepositoryPolls,
        _DiscordChatRepositoryReactions,
        _DiscordChatRepositoryForwards,
        _DiscordChatRepositoryStickers,
        _DiscordChatRepositoryVoiceMessages,
        _DiscordChatRepositoryScheduledEvents
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
  DiscordChatRepository(
    this._api,
    this._gateway,
    this._cache, {
    DiscordMapper? mapper,
    DiscordMessageNonceFactory? messageNonceFactory,
    VoiceDaveService? daveService,
  }) : _mapper = mapper ?? DiscordMapper(),
       _messageNonceFactory =
           messageNonceFactory ?? DiscordMessageNonceFactory(),
       _voiceSignaling = DiscordVoiceSignalingService(
         mainGateway: _gateway,
         nativeDaveService: daveService,
       ) {
    _gatewaySubscription = _gateway.events.listen(_onGatewayEvent);
  }

  @override
  final DiscordApiClient _api;
  final DiscordChatGateway _gateway;
  @override
  final ChatCache _cache;
  @override
  final DiscordMapper _mapper;
  @override
  final DiscordMessageNonceFactory _messageNonceFactory;
  late final DiscordHistoryLoader _historyLoader = DiscordHistoryLoader(
    _api,
    _mapper,
    _cache,
    () => _currentMemberId,
  );
  late final DiscordDirectMessages _directMessages = DiscordDirectMessages(
    _api,
    _cache,
    _mapper,
  );
  late final DiscordChannelHandler _channelHandler = DiscordChannelHandler(
    _cache,
    _mapper,
  );
  late final DiscordGuildMemberLoader _guildMemberLoader =
      DiscordGuildMemberLoader(_api);
  final DiscordVoiceSignalingService _voiceSignaling;
  @override
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  @override
  String? _currentMemberId;
  final Map<String, List<Map<String, Object?>>> _rolesByGuild = {};
  late final DiscordReactionHandler _reactionHandler = DiscordReactionHandler(
    _cache,
    () => _currentMemberId,
  );

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  Future<ChatWorkspace> loadWorkspace() async {
    _events.addStatus(RepositoryConnectionStatus.connecting);
    try {
      final user = await _api.getCurrentUser();
      final guilds = await _api.getCurrentUserGuilds();
      final channelsByGuild = <String, List<Map<String, Object?>>>{};
      final threadsByGuild = <String, List<Map<String, Object?>>>{};
      final membersByGuild = <String, List<Map<String, Object?>>>{};
      final emojisByGuild = <String, List<Map<String, Object?>>>{};
      final stickersByGuild = <String, List<Map<String, Object?>>>{};
      for (final guild in guilds) {
        final guildId = guild['id']! as String;
        channelsByGuild[guildId] = await _api.getGuildChannels(guildId);
        threadsByGuild[guildId] = await _api.getGuildActiveThreads(guildId);
        _rolesByGuild[guildId] = await _api.getGuildRoles(guildId);
        membersByGuild[guildId] = await _guildMemberLoader.load(guildId);
        emojisByGuild[guildId] = await _api.getGuildEmojis(guildId);
        stickersByGuild[guildId] = await _api.getGuildStickers(guildId);
      }
      final cached = await _cache.readWorkspace();
      final workspace = _mapper
          .workspace(
            currentUser: user,
            guilds: guilds,
            channelsByGuild: channelsByGuild,
            threadsByGuild: threadsByGuild,
            membersByGuild: membersByGuild,
            rolesByGuild: _rolesByGuild,
            emojisByGuild: emojisByGuild,
            stickersByGuild: stickersByGuild,
            includeDirectMessagesSpace: true,
          )
          .retainDirectMessagesFrom(cached)
          .restoreChannelActivityFrom(cached);
      _currentMemberId = workspace.currentMemberId;
      _directMessages.seed(workspace.channels);
      _voiceSignaling.setCurrentUserId(workspace.currentMemberId);
      await _cache.writeWorkspace(workspace);
      final gatewayUrl = await _api.getBotGatewayUrl();
      unawaited(_gateway.connect(gatewayUrl));
      return workspace;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readWorkspace();
      if (cached != null) {
        _events.addStatus(RepositoryConnectionStatus.offline);
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) => _historyLoader.load(channelId, beforeMessageId: beforeMessageId);

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) =>
      _loadPinnedMessages(channelId);

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) async {
    final currentUserId = _currentMemberId;
    if (currentUserId == null) {
      throw StateError('Discord workspace is not loaded');
    }
    final conversation = await _directMessages.open(recipientId, currentUserId);
    _emitDirectConversation(conversation);
    return conversation;
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
    autoArchiveDurationMinutes: autoArchiveDurationMinutes,
  );

  @override
  Future<ArchivedThreadPage> loadArchivedThreads(
    String parentChannelId, {
    DateTime? before,
  }) => _loadArchivedThreads(parentChannelId, before: before);

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
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _api.pinMessage(channelId: channelId, messageId: messageId);
    final message = await _cache.readMessage(messageId);
    if (message != null) {
      await _cache.writeMessage(message.copyWith(isPinned: true));
    }
  }

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _api.unpinMessage(channelId: channelId, messageId: messageId);
    final message = await _cache.readMessage(messageId);
    if (message != null) {
      await _cache.writeMessage(message.copyWith(isPinned: false));
    }
  }

  @override
  Future<void> startTyping(String channelId) => _api.startTyping(channelId);

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _cache.writeChannelActivity(channel);

  /// Handed out whole rather than re-exported member by member: the service is
  /// also the media transport the audio pipeline binds to, and forwarding only
  /// the signalling half hid that second face behind the repository.
  @override
  VoiceSignalingService? get voiceSignaling => _voiceSignaling;

  @override
  UserProfileRepository? get userProfile => null;

  @override
  ThreadMembershipRepository? get threadMembership => null;

  /// A bot token has no user account behind it, and `/users/@me/settings-proto`
  /// answers for a user. The capability is absent rather than empty.
  @override
  UserSettingsRepository? get userSettings => null;

  @override
  ReadStateRepository? get readState => null;

  /// A bot cannot be a party to a DM call: Discord grants the private-call
  /// routes to user sessions only, so this transport truthfully has no call
  /// plane rather than one that always fails.
  @override
  DirectCallService? get directCalls => null;

  /// The settings surface gates every control on the *signed-in member's*
  /// permissions and role position, so a bot session would judge a moderator's
  /// buttons by the bot's standing. A bot has no relationship to change either.
  @override
  GuildManagementRepository? get guildManagement => null;

  @override
  ModerationRepository? get moderation => null;

  /// The search routes are scoped to a signed-in user's own session; a
  /// bot token is rejected by them, so this transport has no search plane
  /// rather than one that always fails.
  @override
  MessageSearchRepository? get messageSearch => null;

  /// A bot has no status to broadcast: opcode 3 is accepted on a bot socket
  /// but nothing in Discord's UI shows it, and there is no settings blob for a
  /// custom status to live in. Inbound presence still reaches this transport
  /// as [PresenceChangedEvent]; only the outbound half is absent.
  @override
  PresenceService? get presence => null;

  @override
  Future<void> close() async {
    await _gatewaySubscription.cancel();
    await _voiceSignaling.close();
    await _gateway.close();
    _api.close();
    await _cache.close();
    await _events.close();
  }
}
