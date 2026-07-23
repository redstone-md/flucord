part of 'discord_chat_repository.dart';

mixin _DiscordChatRepositoryPolls implements PollRepository {
  DiscordApiClient get _api;
  DiscordMapper get _mapper;
  ChatCache get _cache;
  String? get _currentMemberId;
  StreamController<ChatRepositoryEvent> get _events;

  late final DiscordPollVoteHandler _pollVoteHandler = DiscordPollVoteHandler(
    _cache,
    () => _currentMemberId,
  );

  Future<void> _handlePollVote(DiscordGatewayDispatch event) async {
    final update = await _pollVoteHandler.apply(event);
    if (update != null && !_events.isClosed) _events.add(update);
  }

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
    final payload = await _api.endPoll(
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
}
