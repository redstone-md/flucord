part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryMessages {
  DiscordDesktopApiClient get _api;
  ChatCache get _cache;
  DiscordMapper get _mapper;
  StreamController<ChatRepositoryEvent> get _events;
  String? get _currentMemberId;
  Future<ChatMessage> _storeSentMessage(Map<String, Object?> payload);
  Future<ChatMessage> _storeMessage(
    Map<String, Object?> payload, {
    ChatMessage? fallback,
  });

  static const _pageSize = 100;

  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
    String? aroundMessageId,
  }) async {
    // The held page goes out first, so the conversation is readable while
    // Discord is still being asked for the same one.
    final restored = beforeMessageId == null && aroundMessageId == null
        ? await readRestoredHistory(_cache, channelId, pageSize: _pageSize)
        : null;
    if (restored != null) _events.add(restored);
    try {
      final payloads = await _api.getChannelMessages(
        channelId,
        limit: _pageSize,
        beforeMessageId: beforeMessageId,
        aroundMessageId: aroundMessageId,
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
      // The page already handed out is the answer; re-reading it would only
      // decode the same rows again.
      if (restored != null) {
        return ChannelHistoryPage(
          history: restored.history,
          hasMore: restored.hasMore,
          fromCache: true,
        );
      }
      final cached = await _cache.readChannelHistory(
        channelId,
        limit: _pageSize,
        beforeMessageId: beforeMessageId,
      );
      if (cached.messages.isEmpty) rethrow;
      return ChannelHistoryPage(
        history: cached,
        hasMore: cached.messages.length >= _pageSize,
        fromCache: true,
      );
    }
  }

  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    required String nonce,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
    bool textToSpeech = false,
    UploadProgressListener? onUploadProgress,
  }) async {
    final payload = await _api.createMessage(
      channelId: channelId,
      content: body,
      nonce: nonce,
      attachments: attachments,
      replyToMessageId: replyToMessageId,
      suppressNotifications: suppressNotifications,
      textToSpeech: textToSpeech,
      onUploadProgress: onUploadProgress,
    );
    return _storeSentMessage(payload);
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
    return _storeMessage(
      payload,
      fallback: await _cache.readMessage(messageId),
    );
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
  }) => _api.resolveAutoModAlert(
    guildId: guildId,
    channelId: channelId,
    messageId: messageId,
    actionType: action.code,
  );

  Future<void> startTyping(String channelId) => _api.startTyping(channelId);
}
