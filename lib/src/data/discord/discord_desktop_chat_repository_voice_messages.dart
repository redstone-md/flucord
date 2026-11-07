part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryVoiceMessages
    implements VoiceMessageRepository {
  DiscordDesktopApiClient get _api;
  Future<ChatMessage> _storeSentMessage(Map<String, Object?> payload);

  @override
  Future<ChatMessage> sendVoiceMessage({
    required String channelId,
    required String authorId,
    required PendingVoiceMessage voiceMessage,
    required String nonce,
    UploadProgressListener? onUploadProgress,
  }) async {
    final payload = await _api.createVoiceMessage(
      channelId: channelId,
      voiceMessage: voiceMessage,
      nonce: nonce,
      onUploadProgress: onUploadProgress,
    );
    return _storeSentMessage(payload);
  }
}
