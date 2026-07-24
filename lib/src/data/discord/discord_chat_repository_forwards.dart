part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryForwards implements MessageForwardRepository {
  DiscordApiClient get _api;
  DiscordMapper get _mapper;
  ChatCache get _cache;
  String? get _currentMemberId;

  @override
  Future<ChatMessage> forwardMessage({
    required String sourceChannelId,
    required String sourceMessageId,
    required String targetChannelId,
  }) async {
    final payload = await _api.forwardMessage(
      sourceChannelId: sourceChannelId,
      sourceMessageId: sourceMessageId,
      targetChannelId: targetChannelId,
    );
    final message = _mapper.message(payload, currentMemberId: _currentMemberId);
    final rawAuthor = payload['author'];
    final member = rawAuthor is Map
        ? _mapper.member(rawAuthor.cast<String, Object?>())
        : null;
    await _cache.writeMessage(message, member: member);
    return message;
  }
}
