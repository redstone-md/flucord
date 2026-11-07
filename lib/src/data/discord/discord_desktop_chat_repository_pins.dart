part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryPins {
  DiscordDesktopApiClient get _api;
  ChatCache get _cache;
  DiscordMapper get _mapper;
  String? get _currentMemberId;

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

  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _setPinned(channelId, messageId, true);

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
}
