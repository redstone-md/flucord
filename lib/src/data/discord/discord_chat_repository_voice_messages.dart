part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryVoiceMessages implements VoiceMessageRepository {
  DiscordApiClient get _api;
  DiscordMapper get _mapper;
  ChatCache get _cache;
  DiscordMessageNonceFactory get _messageNonceFactory;
  String? get _currentMemberId;

  @override
  Future<ChatMessage> sendVoiceMessage({
    required String channelId,
    required String authorId,
    required PendingVoiceMessage voiceMessage,
  }) async {
    final payload = await _api.createVoiceMessage(
      channelId: channelId,
      voiceMessage: voiceMessage,
      nonce: _messageNonceFactory.next(),
      enforceNonce: true,
    );
    final message = _mapper.message(payload, currentMemberId: _currentMemberId);
    await _cache.writeMessage(message);
    return message;
  }
}
