import 'dart:async';

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/forum_repository.dart';
import '../../domain/poll_repository.dart';
import '../../domain/thread_repository.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_api_client.dart';
import 'discord_channel_handler.dart';
import 'discord_direct_messages.dart';
import 'discord_gateway_client.dart';
import 'discord_guild_member_loader.dart';
import 'discord_history_loader.dart';
import 'discord_mapper.dart';
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

final class DiscordChatRepository
    with _DiscordChatRepositoryPolls
    implements
        ChatRepository,
        ArchivedThreadRepository,
        ForumPostRepository,
        PollRepository,
        VoiceSignalingService {
  DiscordChatRepository(
    this._api,
    this._gateway,
    this._cache, {
    DiscordMapper? mapper,
    VoiceDaveService? daveService,
  }) : _mapper = mapper ?? DiscordMapper(),
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
      for (final guild in guilds) {
        final guildId = guild['id']! as String;
        channelsByGuild[guildId] = await _api.getGuildChannels(guildId);
        threadsByGuild[guildId] = await _api.getGuildActiveThreads(guildId);
        _rolesByGuild[guildId] = await _api.getGuildRoles(guildId);
        membersByGuild[guildId] = await _guildMemberLoader.load(guildId);
        emojisByGuild[guildId] = await _api.getGuildEmojis(guildId);
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
            includeDirectMessagesSpace: true,
          )
          .retainDirectMessagesFrom(cached)
          .restoreChannelActivityFrom(cached);
      _currentMemberId = workspace.currentMemberId;
      _directMessages.seed(workspace.channels);
      _voiceSignaling.setCurrentUserId(workspace.currentMemberId);
      await _cache.writeWorkspace(workspace);
      final gatewayUrl = await _api.getGatewayUrl();
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
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
  }) async {
    final payload = await _api.createMessage(
      channelId: channelId,
      content: body,
      attachments: attachments,
      replyToMessageId: replyToMessageId,
    );
    final message = _mapper.message(payload, currentMemberId: _currentMemberId);
    await _cache.writeMessage(message);
    return message;
  }

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) async {
    final payload = await _api.editMessage(
      channelId: channelId,
      messageId: messageId,
      content: body,
    );
    final fallback = await _cache.readMessage(messageId);
    final message = _mapper.message(
      payload,
      fallback: fallback,
      currentMemberId: _currentMemberId,
    );
    await _cache.writeMessage(message);
    return message;
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _api.deleteMessage(channelId: channelId, messageId: messageId);
    await _cache.deleteMessage(messageId);
  }

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

  void _onGatewayEvent(DiscordGatewayEvent event) {
    switch (event) {
      case DiscordGatewayStatusEvent():
        _events.addStatus(switch (event.status) {
          DiscordGatewayStatus.offline => RepositoryConnectionStatus.offline,
          DiscordGatewayStatus.connecting =>
            RepositoryConnectionStatus.connecting,
          DiscordGatewayStatus.connected =>
            RepositoryConnectionStatus.connected,
          DiscordGatewayStatus.reconnecting =>
            RepositoryConnectionStatus.reconnecting,
        });
      case DiscordGatewayDispatch():
        switch (event.name) {
          case 'MESSAGE_CREATE' || 'MESSAGE_UPDATE':
            unawaited(_handleMessageDispatch(event));
          case 'MESSAGE_DELETE':
            unawaited(_handleMessageDelete(event.data));
          case 'MESSAGE_REACTION_ADD' || 'MESSAGE_REACTION_REMOVE':
            unawaited(_handleReaction(event));
          case 'MESSAGE_POLL_VOTE_ADD' || 'MESSAGE_POLL_VOTE_REMOVE':
            unawaited(_handlePollVote(event));
          case 'CHANNEL_CREATE' ||
              'CHANNEL_UPDATE' ||
              'THREAD_CREATE' ||
              'THREAD_UPDATE':
            unawaited(_handleChannelUpsert(event.data));
          case 'CHANNEL_DELETE' || 'THREAD_DELETE':
            unawaited(_handleChannelDelete(event.data));
          case 'GUILD_MEMBER_ADD' || 'GUILD_MEMBER_UPDATE':
            unawaited(_handleMemberUpsert(event.data));
          case 'GUILD_MEMBER_REMOVE':
            _handleMemberRemove(event.data);
          case 'PRESENCE_UPDATE':
            _handlePresence(event.data);
          case 'TYPING_START':
            _handleTyping(event.data);
          case 'CHANNEL_PINS_UPDATE':
            _handlePinsChanged(event.data);
          case 'GUILD_CREATE':
            _handleGuildSnapshot(event.data);
          case 'GUILD_EMOJIS_UPDATE':
            unawaited(_handleGuildEmojis(event.data));
        }
    }
  }

  Future<void> _handleMessageDelete(Map<String, Object?> data) async {
    final messageId = data['id'] as String?;
    final channelId = data['channel_id'] as String?;
    if (messageId == null || channelId == null) return;
    await _cache.deleteMessage(messageId);
    if (!_events.isClosed) {
      _events.add(
        MessageDeletedEvent(messageId: messageId, channelId: channelId),
      );
    }
  }

  Future<void> _handleReaction(DiscordGatewayDispatch event) async {
    final update = await _reactionHandler.apply(event);
    if (update != null && !_events.isClosed) _events.add(update);
  }

  Future<void> _handleChannelUpsert(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId == null) {
      final currentUserId = _currentMemberId;
      if (currentUserId == null) return;
      final conversation = await _directMessages.acceptChannel(
        data,
        currentUserId,
      );
      if (conversation != null) _emitDirectConversation(conversation);
      return;
    }
    final update = await _channelHandler.upsert(data, guildId);
    if (update != null && !_events.isClosed) _events.add(update);
  }

  Future<void> _handleChannelDelete(Map<String, Object?> data) async {
    final update = await _channelHandler.delete(data);
    if (update != null && !_events.isClosed) _events.add(update);
  }

  Future<void> _handleMemberUpsert(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId == null || data['user'] is! Map) return;
    final member = _mapper.guildMember(
      data,
      guildId,
      _rolesByGuild[guildId] ?? const [],
    );
    await _cache.writeMember(member);
    if (!_events.isClosed) _events.add(MemberUpsertedEvent(member));
  }

  void _handleMemberRemove(Map<String, Object?> data) {
    final guildId = data['guild_id'] as String?;
    final user = data['user'];
    final memberId = user is Map ? user['id'] as String? : null;
    if (guildId == null || memberId == null || _events.isClosed) return;
    _events.add(MemberRemovedEvent(memberId: memberId, spaceId: guildId));
  }

  void _handlePresence(Map<String, Object?> data) {
    final user = data['user'];
    final memberId = user is Map ? user['id'] as String? : null;
    final status = data['status'] as String?;
    if (memberId == null || status == null || _events.isClosed) return;
    _events.add(
      PresenceChangedEvent(
        memberId: memberId,
        presence: _mapper.presence(status),
      ),
    );
  }

  void _handleTyping(Map<String, Object?> data) {
    final channelId = data['channel_id'] as String?;
    final memberId = data['user_id'] as String?;
    if (channelId == null || memberId == null || _events.isClosed) return;
    _events.add(TypingStartedEvent(channelId: channelId, memberId: memberId));
  }

  void _handlePinsChanged(Map<String, Object?> data) {
    final channelId = data['channel_id'] as String?;
    if (channelId != null && !_events.isClosed) {
      _events.add(PinsChangedEvent(channelId));
    }
  }

  void _handleGuildSnapshot(Map<String, Object?> data) {
    final guildId = data['id'] as String?;
    if (guildId == null) return;
    if (data['emojis'] is List) unawaited(_handleGuildEmojis(data));
    final roles = data['roles'];
    if (roles is List) {
      _rolesByGuild[guildId] = roles
          .whereType<Map>()
          .map((role) => role.cast<String, Object?>())
          .toList(growable: false);
    }
    final members = data['members'];
    if (members is List && !_events.isClosed) {
      for (final raw in members.whereType<Map>()) {
        final payload = raw.cast<String, Object?>();
        if (payload['user'] is! Map) continue;
        _events.add(
          MemberUpsertedEvent(
            _mapper.guildMember(
              payload,
              guildId,
              _rolesByGuild[guildId] ?? const [],
            ),
          ),
        );
      }
    }
    final presences = data['presences'];
    if (presences is List) {
      for (final raw in presences.whereType<Map>()) {
        _handlePresence(raw.cast<String, Object?>());
      }
    }
  }

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _voiceSignaling.voiceEvents;

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  }) => _voiceSignaling.joinVoiceChannel(
    guildId: guildId,
    channelId: channelId,
    selfMute: selfMute,
    selfDeaf: selfDeaf,
  );

  @override
  Future<void> leaveVoiceChannel(String guildId) =>
      _voiceSignaling.leaveVoiceChannel(guildId);

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
