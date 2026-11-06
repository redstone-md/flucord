part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryPolls implements PollRepository, PollVoteRepository {
  ChatWorkspace get _workspace;
  set _workspace(ChatWorkspace value);
  int get _messageSequence;
  set _messageSequence(int value);
  Future<void> _wait();

  @override
  Future<ChatMessage> createPoll({
    required String channelId,
    required String authorId,
    required PendingPoll poll,
  }) async {
    await _wait();
    final now = DateTime.now();
    final message = ChatMessage(
      id: 'local-${_messageSequence++}',
      channelId: channelId,
      authorId: authorId,
      body: '',
      sentAt: now,
      poll: MessagePoll(
        question: poll.question,
        answers: [
          for (var index = 0; index < poll.answers.length; index++)
            PollAnswer(id: index + 1, text: poll.answers[index], count: 0),
        ],
        expiry: now.add(Duration(hours: poll.durationHours)),
        allowMultiselect: poll.allowMultiselect,
        isFinalized: false,
      ),
    );
    _workspace = _workspace.upsertMessage(message);
    return message;
  }

  @override
  Future<ChatMessage> votePoll({
    required String channelId,
    required String messageId,
    required Set<int> answerIds,
  }) async {
    await _wait();
    final message = _pollMessage(channelId, messageId);
    final updated = message.copyWith(
      poll: message.poll!.withOwnVote(answerIds),
    );
    _workspace = _workspace.upsertMessage(updated);
    return updated;
  }

  /// The mock keeps counts, not names, so the account stands first among
  /// its own answers and other members fill the rest of the count.
  @override
  Future<PollVotersPage> loadPollVoters({
    required String channelId,
    required String messageId,
    required int answerId,
    String? afterUserId,
    int limit = 100,
  }) async {
    await _wait();
    final answer = _pollMessage(
      channelId,
      messageId,
    ).poll!.answers.firstWhere((candidate) => candidate.id == answerId);
    final selfId = _workspace.currentMemberId;
    final voters = [
      if (answer.votedByCurrentUser) ?_workspace.memberOrNull(selfId),
      ..._workspace.members.where((member) => member.id != selfId),
    ].take(answer.count).toList(growable: false);
    final start = afterUserId == null
        ? 0
        : voters.indexWhere((member) => member.id == afterUserId) + 1;
    final end = (start + limit.clamp(1, 100)).clamp(0, voters.length);
    return PollVotersPage(
      users: voters.sublist(start, end),
      hasMore: end < voters.length,
    );
  }

  ChatMessage _pollMessage(String channelId, String messageId) {
    final message = _workspace.messages.firstWhere(
      (candidate) =>
          candidate.id == messageId && candidate.channelId == channelId,
    );
    if (message.poll == null) {
      throw StateError('Message does not contain a poll');
    }
    return message;
  }

  @override
  Future<ChatMessage> endPoll({
    required String channelId,
    required String messageId,
  }) async {
    await _wait();
    final message = _pollMessage(channelId, messageId);
    final updated = message.copyWith(
      poll: message.poll!.copyWith(expiry: DateTime.now(), isFinalized: true),
    );
    _workspace = _workspace.upsertMessage(updated);
    return updated;
  }
}
