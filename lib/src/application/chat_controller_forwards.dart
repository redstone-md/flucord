part of 'chat_controller.dart';

extension ChatControllerForwards on ChatController {
  Future<bool> forwardMessage(
    ChatMessage source,
    String targetChannelId,
  ) async {
    final workspace = _workspace;
    final repository = _repository is MessageForwardRepository
        ? _repository as MessageForwardRepository
        : null;
    final target = workspace?.channelOrNull(targetChannelId);
    if (workspace == null ||
        repository == null ||
        !source.canForward ||
        !workspace
            .messagesFor(source.channelId)
            .any((message) => message.id == source.id) ||
        target == null ||
        !target.canAcceptMessageForward ||
        _isSending) {
      return false;
    }
    _isSending = true;
    _notify();
    try {
      final forwarded = await repository.forwardMessage(
        sourceChannelId: source.channelId,
        sourceMessageId: source.id,
        targetChannelId: targetChannelId,
      );
      _applySentMessage(forwarded);
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
