part of 'discord_desktop_chat_repository.dart';

mixin _DiscordDesktopChatRepositoryPolls
    implements PollRepository, PollVoteRepository {
  DiscordDesktopApiClient get _api;
  ChatCache get _cache;
  DiscordMapper get _mapper;
  DiscordMessageNonceFactory get _nonceFactory;
  DiscordSharedDispatches get _sharedDispatches;
  Future<ChatMessage> _storeSentMessage(Map<String, Object?> payload);
  Future<ChatMessage> _storeMessage(
    Map<String, Object?> payload, {
    ChatMessage? fallback,
  });

  @override
  Future<ChatMessage> createPoll({
    required String channelId,
    required String authorId,
    required PendingPoll poll,
  }) async => _storeSentMessage(
    await _api.createMessage(
      channelId: channelId,
      content: '',
      nonce: _nonceFactory.next(),
      poll: poll,
    ),
  );

  @override
  Future<ChatMessage> endPoll({
    required String channelId,
    required String messageId,
  }) async => _storeMessage(
    await _api.polls.endPoll(channelId: channelId, messageId: messageId),
    fallback: await _cache.readMessage(messageId),
  );

  /// Discord answers a vote with no body, so the vote is counted here, on the
  /// dispatch queue so a vote from somebody else is not written over. The
  /// count only marks the account's own vote, so it and the dispatches that
  /// echo it change nothing a second time, in whichever order they come.
  @override
  Future<ChatMessage> votePoll({
    required String channelId,
    required String messageId,
    required Set<int> answerIds,
  }) async {
    await _api.polls.vote(
      channelId: channelId,
      messageId: messageId,
      answerIds: answerIds.toList()..sort(),
    );
    return _sharedDispatches.queued(() async {
      final held = await _cache.readMessage(messageId);
      final poll = held?.poll;
      if (held == null || poll == null) {
        throw StateError('Poll message $messageId is not in the cache');
      }
      final voted = held.copyWith(poll: poll.withOwnVote(answerIds));
      await _cache.writeMessage(voted);
      return voted;
    });
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
