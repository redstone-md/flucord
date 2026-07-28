part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryMessageMutations implements MessageFlagRepository {
  DiscordApiClient get _api;
  DiscordMapper get _mapper;
  ChatCache get _cache;
  String? get _currentMemberId;
  DiscordMessageNonceFactory get _messageNonceFactory;

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
      attachments: attachments,
      replyToMessageId: replyToMessageId,
      nonce: _messageNonceFactory.next(),
      enforceNonce: true,
      suppressNotifications: suppressNotifications,
    );
    final message = _mapper.message(payload, currentMemberId: _currentMemberId);
    await _cache.writeMessage(message);
    return message;
  }

  @override
  Future<ChatMessage> setSuppressEmbeds({
    required String channelId,
    required String messageId,
    required bool suppress,
  }) async {
    final fallback = await _cache.readMessage(messageId);
    final payload = await _api.editMessageFlags(
      channelId: channelId,
      messageId: messageId,
      suppressEmbeds: suppress,
      componentsV2: fallback?.hasFlag(DiscordMessageFlag.componentsV2) ?? false,
    );
    final message = _mapper.message(
      payload,
      fallback: fallback,
      currentMemberId: _currentMemberId,
    );
    await _cache.writeMessage(message);
    return message;
  }

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

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _api.deleteMessage(channelId: channelId, messageId: messageId);
    await _cache.deleteMessage(messageId);
  }

  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
  }) async {}
}

extension _DiscordChatRepositoryMessages on DiscordChatRepository {
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
    final message = _mapper.message(
      event.data,
      fallback: fallback,
      currentMemberId: _currentMemberId,
    );
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
    if (_events.isClosed) return;
    _events.add(
      MessageUpsertedEvent(
        message: message,
        member: member,
        isNew: event.name == 'MESSAGE_CREATE',
        mentionsCurrentMember: message.mentionsCurrentMember,
      ),
    );
  }

  void _emitDirectConversation(DirectConversation conversation) {
    if (_events.isClosed) return;
    _events.add(SpaceUpsertedEvent(_directMessages.space));
    _events.add(MemberUpsertedEvent(conversation.recipient));
    _events.add(ChannelUpsertedEvent(conversation.channel));
  }
}
