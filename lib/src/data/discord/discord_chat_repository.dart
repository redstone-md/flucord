import 'dart:async';

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_api_client.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';

final class DiscordChatRepository implements ChatRepository {
  DiscordChatRepository(
    this._api,
    this._gateway,
    this._cache, {
    DiscordMapper? mapper,
  }) : _mapper = mapper ?? DiscordMapper() {
    _gatewaySubscription = _gateway.events.listen(_onGatewayEvent);
  }

  final DiscordApiClient _api;
  final DiscordGatewayClient _gateway;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  String? _currentMemberId;
  final Map<String, List<Map<String, Object?>>> _rolesByGuild = {};

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
        membersByGuild[guildId] = await _loadGuildMembers(guildId);
      }
      final workspace = _mapper.workspace(
        currentUser: user,
        guilds: guilds,
        channelsByGuild: channelsByGuild,
        threadsByGuild: threadsByGuild,
        membersByGuild: membersByGuild,
        rolesByGuild: _rolesByGuild,
      );
      _currentMemberId = workspace.currentMemberId;
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

  Future<List<Map<String, Object?>>> _loadGuildMembers(String guildId) async {
    try {
      return await _api.getGuildMembers(guildId);
    } on DiscordApiException catch (error) {
      if (error.isForbidden) return const [];
      rethrow;
    }
  }

  @override
  Future<ChannelHistory> loadChannelHistory(String channelId) async {
    try {
      final payloads = await _api.getChannelMessages(channelId);
      final history = _mapper.history(channelId, payloads);
      await _cache.writeChannelHistory(history);
      return history;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readChannelHistory(channelId);
      if (cached.messages.isNotEmpty) return cached;
      rethrow;
    }
  }

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
          case 'THREAD_CREATE' || 'THREAD_UPDATE':
            unawaited(_handleThreadUpsert(event.data));
          case 'THREAD_DELETE':
            unawaited(_handleThreadDelete(event.data));
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
    final messageId = event.data['message_id'] as String?;
    final emojiPayload = event.data['emoji'];
    if (messageId == null || emojiPayload is! Map) return;
    final message = await _cache.readMessage(messageId);
    if (message == null) return;
    final emoji = emojiPayload.cast<String, Object?>();
    final name = emoji['name'] as String?;
    if (name == null) return;
    final id = emoji['id'] as String?;
    final key = id == null ? name : '$name:$id';
    final add = event.name == 'MESSAGE_REACTION_ADD';
    final byCurrentUser = event.data['user_id'] == _currentMemberId;
    final reactions = [...message.reactions];
    final index = reactions.indexWhere((reaction) => reaction.key == key);
    if (index < 0 && add) {
      reactions.add(
        MessageReaction(
          emojiName: name,
          emojiId: id,
          animated: emoji['animated'] as bool? ?? false,
          count: 1,
          reactedByCurrentUser: byCurrentUser,
        ),
      );
    } else if (index >= 0) {
      final current = reactions[index];
      final count = current.count + (add ? 1 : -1);
      if (count <= 0) {
        reactions.removeAt(index);
      } else {
        reactions[index] = current.copyWith(
          count: count,
          reactedByCurrentUser: byCurrentUser
              ? add
              : current.reactedByCurrentUser,
        );
      }
    }
    final updated = message.copyWith(reactions: reactions);
    await _cache.writeMessage(updated);
    if (!_events.isClosed) {
      _events.add(MessageUpsertedEvent(message: updated));
    }
  }

  Future<void> _handleThreadUpsert(Map<String, Object?> data) async {
    final guildId = data['guild_id'] as String?;
    if (guildId == null) return;
    final channel = _mapper.channel(data, guildId);
    if (channel == null) return;
    await _cache.writeChannel(channel);
    if (!_events.isClosed) _events.add(ChannelUpsertedEvent(channel));
  }

  Future<void> _handleThreadDelete(Map<String, Object?> data) async {
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
  Future<void> close() async {
    await _gatewaySubscription.cancel();
    await _gateway.close();
    _api.close();
    await _cache.close();
    await _events.close();
  }
}
