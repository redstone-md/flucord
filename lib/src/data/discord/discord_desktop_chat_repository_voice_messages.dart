part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryVoiceMessages
    implements VoiceMessageRepository {
  DiscordDesktopApiClient get _api;
  DiscordMessageNonceFactory get _nonceFactory;
  Future<ChatMessage> _storeSentMessage(Map<String, Object?> payload);

  @override
  Future<ChatMessage> sendVoiceMessage({
    required String channelId,
    required String authorId,
    required PendingVoiceMessage voiceMessage,
  }) async {
    // As a draft with the file only, so a retry keeps its nonce.
    final payload = await _nonceFactory.sendDraft(
      channelId: channelId,
      body: '',
      attachments: [voiceMessage.attachment],
      replyToMessageId: null,
      suppressNotifications: false,
      textToSpeech: false,
      send: (nonce) => _api.createVoiceMessage(
        channelId: channelId,
        voiceMessage: voiceMessage,
        nonce: nonce,
      ),
    );
    return _storeSentMessage(payload);
  }
}
