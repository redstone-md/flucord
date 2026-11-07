part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryForwards
    implements MessageForwardRepository {
  DiscordDesktopApiClient get _api;
  DiscordMessageNonceFactory get _nonceFactory;
  Future<ChatMessage> _storeSentMessage(Map<String, Object?> payload);

  /// A forward is a send with no words of its own: the reference names the
  /// source, and Discord answers with the snapshot it took.
  @override
  Future<ChatMessage> forwardMessage({
    required String sourceChannelId,
    required String sourceMessageId,
    required String targetChannelId,
  }) async => _storeSentMessage(
    await _api.createMessage(
      channelId: targetChannelId,
      content: '',
      nonce: _nonceFactory.next(),
      forwardOf: (channelId: sourceChannelId, messageId: sourceMessageId),
    ),
  );
}
