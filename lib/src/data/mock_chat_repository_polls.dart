part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryPolls implements PollRepository {
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
  Future<ChatMessage> endPoll({
    required String channelId,
    required String messageId,
  }) async {
    await _wait();
    final message = _workspace.messages.firstWhere(
      (candidate) =>
          candidate.id == messageId && candidate.channelId == channelId,
    );
    final poll = message.poll;
    if (poll == null) throw StateError('Message does not contain a poll');
    final updated = message.copyWith(
      poll: poll.copyWith(expiry: DateTime.now(), isFinalized: true),
    );
    _workspace = _workspace.upsertMessage(updated);
    return updated;
  }
}
