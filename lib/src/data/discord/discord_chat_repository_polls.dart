part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryPolls implements PollRepository {
  DiscordApiClient get _api;
  DiscordMapper get _mapper;
  ChatCache get _cache;
  DiscordMessageNonceFactory get _messageNonceFactory;
  String? get _currentMemberId;

  @override
  Future<ChatMessage> createPoll({
    required String channelId,
    required String authorId,
    required PendingPoll poll,
  }) async {
    final payload = await _api.createMessage(
      channelId: channelId,
      content: '',
      poll: poll,
      nonce: _messageNonceFactory.next(),
      enforceNonce: true,
    );
    final message = _mapper.message(payload, currentMemberId: _currentMemberId);
    await _cache.writeMessage(message);
    return message;
  }

  @override
  Future<ChatMessage> endPoll({
    required String channelId,
    required String messageId,
  }) async {
    final payload = await _api.polls.endPoll(
      channelId: channelId,
      messageId: messageId,
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

  @override
  Future<MemberPage> loadPollVoters({
    required String channelId,
    required String messageId,
    required int answerId,
    String? afterUserId,
    int limit = 100,
  }) => _api.polls.answerVoters(
    channelId: channelId,
    messageId: messageId,
    answerId: answerId,
    mapper: _mapper,
    afterUserId: afterUserId,
    limit: limit,
  );
}
