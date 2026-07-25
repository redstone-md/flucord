import 'dart:async';

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_desktop_api_client.dart';
import 'discord_desktop_gateway_client.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';
import 'discord_message_nonce_factory.dart';
import 'discord_rest_client.dart';

final class DiscordDesktopChatRepository implements ChatRepository {
  DiscordDesktopChatRepository(
    this._api,
    this._gateway,
    this._cache, {
    DiscordMapper? mapper,
    DiscordMessageNonceFactory? nonceFactory,
  }) : _mapper = mapper ?? DiscordMapper(),
       _nonceFactory = nonceFactory ?? DiscordMessageNonceFactory() {
    _gatewaySubscription = _gateway.events.listen(_acceptGatewayEvent);
  }

  static const _pageSize = 100;

  final DiscordDesktopApiClient _api;
  final DiscordDesktopGatewayClient _gateway;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final DiscordMessageNonceFactory _nonceFactory;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  String? _currentMemberId;

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  Future<ChatWorkspace> loadWorkspace() async {
    _emitStatus(RepositoryConnectionStatus.connecting);
    try {
      final snapshot = await _gateway.connectAndReadWorkspace(
        await _api.getGatewayUrl(),
      );
      final cached = await _cache.readWorkspace();
      final workspace = _mapper
          .workspace(
            currentUser: snapshot.currentUser,
            guilds: snapshot.guilds,
            channelsByGuild: snapshot.channelsByGuild,
            directChannels: snapshot.directChannels,
            includeDirectMessagesSpace: true,
            currentUserRole: 'Discord user',
          )
          .restoreChannelActivityFrom(cached);
      _currentMemberId = workspace.currentMemberId;
      await _cache.writeWorkspace(workspace);
      return workspace;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readWorkspace();
      if (cached != null) {
        _currentMemberId = cached.currentMemberId;
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
  }) async {
    try {
      final payloads = await _api.getChannelMessages(
        channelId,
        limit: _pageSize,
        beforeMessageId: beforeMessageId,
      );
      final history = _mapper.history(
        channelId,
        payloads,
        currentMemberId: _currentMemberId,
      );
      await _cache.writeChannelHistory(history, replaceExisting: false);
      return ChannelHistoryPage(
        history: history,
        hasMore: payloads.length == _pageSize,
      );
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readChannelHistory(channelId);
      if (cached.messages.isEmpty) rethrow;
      return ChannelHistoryPage(history: cached, hasMore: false);
    }
  }

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) async {
    try {
      final history = _mapper.history(
        channelId,
        await _api.getChannelPins(channelId),
        currentMemberId: _currentMemberId,
      );
      for (final message in history.messages) {
        await _cache.writeMessage(message);
      }
      return history;
    } on Object {
      return _cache.readPinnedMessages(channelId);
    }
  }

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) async {
    final currentUserId = _currentMemberId;
    if (currentUserId == null) throw StateError('Workspace is not loaded');
    final mapped = _mapper.directMessage(
      await _api.createDirectMessageChannel(recipientId),
      currentUserId,
    );
    if (mapped == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned an invalid direct message channel',
      );
    }
    await _cache.writeSpace(_mapper.directMessagesSpace);
    await _cache.writeChannel(mapped.channel);
    await _cache.writeMember(mapped.recipient);
    _events.add(SpaceUpsertedEvent(_mapper.directMessagesSpace));
    _events.add(ChannelUpsertedEvent(mapped.channel));
    _events.add(MemberUpsertedEvent(mapped.recipient));
    return DirectConversation(
      channel: mapped.channel,
      recipient: mapped.recipient,
    );
  }

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) async {
    final workspace = await _cache.readWorkspace();
    final parent = workspace?.channelOrNull(channelId);
    if (parent == null) throw StateError('Parent channel is not cached');
    final payload = await _api.createThreadFromMessage(
      channelId: channelId,
      messageId: messageId,
      name: name,
      autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    );
    final channel = _mapper.channel(payload, parent.spaceId);
    if (channel == null) throw StateError('Discord returned an invalid thread');
    await _cache.writeChannel(channel);
    _events.add(ChannelUpsertedEvent(channel));
    return channel;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) async {
    final payload = await _api.createMessage(
      channelId: channelId,
      content: body,
      nonce: _nonceFactory.next(),
      attachments: attachments,
      replyToMessageId: replyToMessageId,
      suppressNotifications: suppressNotifications,
    );
    return _storeMessage(payload);
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
    return _storeMessage(
      payload,
      fallback: await _cache.readMessage(messageId),
    );
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
  }) => _setPinned(channelId, messageId, true);

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) => _setPinned(channelId, messageId, false);

  Future<void> _setPinned(
    String channelId,
    String messageId,
    bool pinned,
  ) async {
    await _api.setPinned(
      channelId: channelId,
      messageId: messageId,
      pinned: pinned,
    );
    final message = await _cache.readMessage(messageId);
    if (message != null) {
      await _cache.writeMessage(message.copyWith(isPinned: pinned));
    }
  }

  @override
  Future<void> startTyping(String channelId) => _api.startTyping(channelId);

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _cache.writeChannelActivity(channel);

  void _acceptGatewayEvent(DiscordGatewayEvent event) {
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
        if (event.name == 'MESSAGE_CREATE' || event.name == 'MESSAGE_UPDATE') {
          unawaited(_acceptMessage(event));
        } else if (event.name == 'MESSAGE_DELETE') {
          unawaited(_acceptDelete(event.data));
        } else if (event.name == 'TYPING_START') {
          _acceptTyping(event.data);
        }
    }
  }

  Future<void> _acceptMessage(DiscordGatewayDispatch event) async {
    final messageId = event.data['id'];
    if (messageId is! String) return;
    final fallback = event.name == 'MESSAGE_UPDATE'
        ? await _cache.readMessage(messageId)
        : null;
    if (event.name == 'MESSAGE_UPDATE' && fallback == null) return;
    final message = await _storeMessage(event.data, fallback: fallback);
    final rawAuthor = event.data['author'];
    final member = rawAuthor is Map
        ? _mapper.member(
            rawAuthor.cast<String, Object?>(),
            spaceIds: {
              if (event.data['guild_id'] case final String guildId) guildId,
              if (event.data['guild_id'] == null)
                DiscordMapper.directMessagesSpaceId,
            },
          )
        : null;
    if (member != null) await _cache.writeMember(member);
    _events.add(
      MessageUpsertedEvent(
        message: message,
        member: member,
        isNew: event.name == 'MESSAGE_CREATE',
        mentionsCurrentMember: message.mentionsCurrentMember,
      ),
    );
  }

  Future<ChatMessage> _storeMessage(
    Map<String, Object?> payload, {
    ChatMessage? fallback,
  }) async {
    final message = _mapper.message(
      payload,
      fallback: fallback,
      currentMemberId: _currentMemberId,
    );
    await _cache.writeMessage(message);
    return message;
  }

  Future<void> _acceptDelete(Map<String, Object?> data) async {
    final messageId = data['id'];
    final channelId = data['channel_id'];
    if (messageId is! String || channelId is! String) return;
    await _cache.deleteMessage(messageId);
    _events.add(
      MessageDeletedEvent(messageId: messageId, channelId: channelId),
    );
  }

  void _acceptTyping(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    final memberId = data['user_id'];
    if (channelId is String && memberId is String) {
      _events.add(TypingStartedEvent(channelId: channelId, memberId: memberId));
    }
  }

  void _emitStatus(RepositoryConnectionStatus status) {
    if (!_events.isClosed) _events.add(RepositoryStatusChangedEvent(status));
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
