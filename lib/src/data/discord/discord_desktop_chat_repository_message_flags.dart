part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryMessageFlags
    implements MessageFlagRepository {
  DiscordDesktopApiClient get _api;
  ChatCache get _cache;
  Future<ChatMessage> _storeMessage(
    Map<String, Object?> payload, {
    ChatMessage? fallback,
  });

  @override
  Future<ChatMessage> setSuppressEmbeds({
    required String channelId,
    required String messageId,
    required bool suppress,
  }) async {
    final held = await _cache.readMessage(messageId);
    final payload = await _api.editMessageFlags(
      channelId: channelId,
      messageId: messageId,
      suppressEmbeds: suppress,
      componentsV2: held?.hasFlag(DiscordMessageFlag.componentsV2) ?? false,
    );
    return _storeMessage(payload, fallback: held);
  }
}
