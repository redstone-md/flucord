part of 'chat_controller.dart';

extension ChatControllerPolls on ChatController {
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
        !normalized.isValid ||
        _isSending) {
      return false;
    }
    _isSending = true;
    _notify();
    try {
      final message = await repository.createPoll(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        poll: normalized,
      );
      _workspace = _workspace
          ?.upsertMessage(message)
          .clearChannelUnreadBoundary(channelId);
      _persistChannelActivity(channelId);
      _error = null;
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
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
        message.poll!.isFinalized ||
        _isSending) {
      return false;
    }
    _isSending = true;
    _notify();
    try {
      final updated = await repository.endPoll(
        channelId: message.channelId,
        messageId: message.id,
      );
      _workspace = _workspace?.upsertMessage(updated);
      _error = null;
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
  }
}
