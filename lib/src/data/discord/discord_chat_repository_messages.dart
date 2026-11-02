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
    bool textToSpeech = false,
  }) async {
    final payload = await _messageNonceFactory.sendDraft(
      channelId: channelId,
      body: body,
      attachments: attachments,
      replyToMessageId: replyToMessageId,
      suppressNotifications: suppressNotifications,
      textToSpeech: textToSpeech,
      send: (nonce) => _api.createMessage(
        channelId: channelId,
        content: body,
        attachments: attachments,
        replyToMessageId: replyToMessageId,
        nonce: nonce,
        enforceNonce: true,
        suppressNotifications: suppressNotifications,
        textToSpeech: textToSpeech,
      ),
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
  Future<void> _handleNewMessage(Map<String, Object?> payload) async {
    if (payload['id'] is! String) return;
    final currentUserId = _currentMemberId;
    if (currentUserId != null) {
      await _directMessages.acceptMessage(payload, currentUserId);
    }
    final message = _mapper.message(payload, currentMemberId: currentUserId);
    final member = _mapper.messageAuthor(payload);
    await _cache.writeMessage(message, member: member);
    _events.add(
      MessageUpsertedEvent(
        message: message,
        member: member,
        isNew: true,
        mentionsCurrentMember: message.mentionsCurrentMember,
      ),
    );
  }
}
