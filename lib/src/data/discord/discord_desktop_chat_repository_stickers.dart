part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryStickers implements StickerRepository {
  DiscordDesktopApiClient get _api;
  DiscordMessageNonceFactory get _nonceFactory;
  Future<ChatMessage> _storeSentMessage(Map<String, Object?> payload);

  @override
  Future<ChatMessage> sendStickers({
    required String channelId,
    required String authorId,
    required List<String> stickerIds,
  }) async {
    if (stickerIds.isEmpty) {
      throw ArgumentError.value(stickerIds, 'stickerIds', 'must contain 1-3');
    }
    return _storeSentMessage(
      await _api.createMessage(
        channelId: channelId,
        content: '',
        nonce: _nonceFactory.next(),
        stickerIds: stickerIds,
      ),
    );
  }
}
