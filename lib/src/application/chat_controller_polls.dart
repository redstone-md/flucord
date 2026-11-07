part of 'chat_controller.dart';

extension ChatControllerPolls on ChatController {
  /// Whether this session's transport can vote in polls. A bot cannot.
  bool get canVoteInPolls => _repository is PollVoteRepository;

  /// Whether this session's transport can list who voted for an answer.
  bool get canListPollVoters => _repository is PollRepository;

  Future<bool> createPoll({
    required String channelId,
    required PendingPoll poll,
  }) async {
    final workspace = _workspace;
    final repository = _repository is PollRepository
        ? _repository as PollRepository
        : null;
    final channel = workspace?.channelOrNull(channelId);
    final normalized = poll.normalized();
    if (workspace == null ||
        repository == null ||
        channel?.hasMessageTimeline != true ||
        !normalized.isValid) {
      return false;
    }
    return _sendingIn(channelId, () async {
      final message = await repository.createPoll(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        poll: normalized,
      );
      _applySentMessage(message);
    });
  }

  Future<bool> endPoll(ChatMessage message) async {
    final workspace = _workspace;
    final repository = _repository is PollRepository
        ? _repository as PollRepository
        : null;
    if (workspace == null ||
        repository == null ||
        message.authorId != workspace.currentMemberId ||
        message.poll == null ||
        message.poll!.isFinalized) {
      return false;
    }
    return _sendingIn(message.channelId, () async {
      final updated = await repository.endPoll(
        channelId: message.channelId,
        messageId: message.id,
      );
      _workspace = _workspace?.upsertMessage(updated);
    });
  }

  /// Makes [answerIds] the account's whole vote in [message]'s poll. An empty
  /// set takes the vote back. An ended poll takes no vote.
  Future<bool> votePoll(ChatMessage message, Set<int> answerIds) async {
    final repository = _repository is PollVoteRepository
        ? _repository as PollVoteRepository
        : null;
    final poll = message.poll;
    if (repository == null ||
        poll == null ||
        !poll.isOpenAt(DateTime.now()) ||
        (!poll.allowMultiselect && answerIds.length > 1)) {
      return false;
    }
    // Locked per poll, not per channel: a vote creates no message, so a
    // message on its way in the channel must not turn the vote away.
    return _sendingIn('poll-vote:${message.id}', what: 'poll vote', () async {
      final updated = await repository.votePoll(
        channelId: message.channelId,
        messageId: message.id,
        answerIds: answerIds,
      );
      _workspace = _workspace?.upsertMessage(updated);
    });
  }

  Future<MemberPage> loadPollVoters(
    ChatMessage message,
    PollAnswer answer,
    String? afterUserId,
  ) {
    final repository = _repository;
    if (repository is! PollRepository) {
      return Future.value(const MemberPage(users: [], hasMore: false));
    }
    return (repository as PollRepository).loadPollVoters(
      channelId: message.channelId,
      messageId: message.id,
      answerId: answer.id,
      afterUserId: afterUserId,
    );
  }
}
