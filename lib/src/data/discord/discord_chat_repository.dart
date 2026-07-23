import 'dart:async';

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_api_client.dart';
import 'discord_direct_messages.dart';
import 'discord_gateway_client.dart';
import 'discord_guild_member_loader.dart';
import 'discord_history_loader.dart';
import 'discord_mapper.dart';
import 'discord_reaction_handler.dart';
import 'discord_voice_signaling_service.dart';

final class DiscordChatRepository
    implements ChatRepository, VoiceSignalingService {
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

  final DiscordApiClient _api;
  final DiscordChatGateway _gateway;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  late final DiscordHistoryLoader _historyLoader = DiscordHistoryLoader(
    _api,
    _mapper,
    _cache,
  );
  late final DiscordDirectMessages _directMessages = DiscordDirectMessages(
    _api,
    _cache,
    _mapper,
  );
  late final DiscordGuildMemberLoader _guildMemberLoader =
      DiscordGuildMemberLoader(_api);
  final DiscordVoiceSignalingService _voiceSignaling;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
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
    _emitStatus(RepositoryConnectionStatus.connecting);
    try {
      final user = await _api.getCurrentUser();
      final guilds = await _api.getCurrentUserGuilds();
      final channelsByGuild = <String, List<Map<String, Object?>>>{};
      final threadsByGuild = <String, List<Map<String, Object?>>>{};
      final membersByGuild = <String, List<Map<String, Object?>>>{};
      for (final guild in guilds) {
        final guildId = guild['id']! as String;
        channelsByGuild[guildId] = await _api.getGuildChannels(guildId);
        threadsByGuild[guildId] = await _api.getGuildActiveThreads(guildId);
        _rolesByGuild[guildId] = await _api.getGuildRoles(guildId);
        membersByGuild[guildId] = await _guildMemberLoader.load(guildId);
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
            includeDirectMessagesSpace: true,
          )
          .retainDirectMessagesFrom(cached);
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
        _emitStatus(RepositoryConnectionStatus.offline);
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
  Future<ChannelHistory> loadPinnedMessages(String channelId) async {
    try {
      final history = _mapper.history(
        channelId,
        await _api.getChannelPins(channelId),
      );
      for (final member in history.members) {
        await _cache.writeMember(member);
      }
      for (final message in history.messages) {
        await _cache.writeMessage(message);
      }
      return history;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readPinnedMessages(channelId);
      if (cached.messages.isNotEmpty) return cached;
      rethrow;
    }
  }

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
    final message = _mapper.message(payload);
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
    final message = _mapper.message(payload, fallback: fallback);
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

  void _onGatewayEvent(DiscordGatewayEvent event) {
    switch (event) {
      case DiscordGatewayStatusEvent():
        _emitStatus(switch (event.status) {
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
    final channel = _mapper.channel(data, guildId);
    if (channel == null) return;
    await _cache.writeChannel(channel);
    if (!_events.isClosed) _events.add(ChannelUpsertedEvent(channel));
  }

  Future<void> _handleChannelDelete(Map<String, Object?> data) async {
    final channelId = data['id'] as String?;
    if (channelId == null) return;
    await _cache.deleteChannel(channelId);
    if (!_events.isClosed) _events.add(ChannelDeletedEvent(channelId));
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

  Future<void> _handleMessageDispatch(DiscordGatewayDispatch event) async {
    final messageId = event.data['id'] as String?;
    if (messageId == null) return;
    final currentUserId = _currentMemberId;
    if (event.name == 'MESSAGE_CREATE' && currentUserId != null) {
      final conversation = await _directMessages.acceptMessage(
        event.data,
        currentUserId,
      );
      if (conversation != null) _emitDirectConversation(conversation);
    }
    final fallback = event.name == 'MESSAGE_UPDATE'
        ? await _cache.readMessage(messageId)
        : null;
    if (event.name == 'MESSAGE_UPDATE' && fallback == null) return;
    final message = _mapper.message(event.data, fallback: fallback);
    final authorPayload = event.data['author'];
    final member = authorPayload is Map
        ? _mapper.member(
            authorPayload.cast<String, Object?>(),
            spaceIds: {
              if (event.data['guild_id'] case final String guildId) guildId,
              if (event.data['guild_id'] == null)
                DiscordMapper.directMessagesSpaceId,
            },
          )
        : null;
    await _cache.writeMessage(message, member: member);
    if (!_events.isClosed) {
      _events.add(
        MessageUpsertedEvent(
          message: message,
          member: member,
          isNew: event.name == 'MESSAGE_CREATE',
          mentionsCurrentMember: _mentionsCurrentMember(event.data),
        ),
      );
    }
  }

  void _emitDirectConversation(DirectConversation conversation) {
    if (_events.isClosed) return;
    _events.add(SpaceUpsertedEvent(_directMessages.space));
    _events.add(MemberUpsertedEvent(conversation.recipient));
    _events.add(ChannelUpsertedEvent(conversation.channel));
  }

  bool _mentionsCurrentMember(Map<String, Object?> data) {
    final memberId = _currentMemberId;
    if (memberId == null) return false;
    final mentions = data['mentions'];
    return mentions is List &&
        mentions.whereType<Map>().any((user) => user['id'] == memberId);
  }

  void _emitStatus(RepositoryConnectionStatus status) {
    if (!_events.isClosed) {
      _events.add(RepositoryStatusChangedEvent(status));
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
