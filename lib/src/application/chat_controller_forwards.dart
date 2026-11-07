part of 'chat_controller.dart';

extension ChatControllerForwards on ChatController {
  /// Whether this session's transport can forward messages at all.
  bool get canForwardMessages => _repository is MessageForwardRepository;

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
        !target.canAcceptMessageForward) {
      return false;
    }
    return _sendingIn(targetChannelId, () async {
      final forwarded = await repository.forwardMessage(
        sourceChannelId: source.channelId,
        sourceMessageId: source.id,
        targetChannelId: targetChannelId,
      );
      _applySentMessage(forwarded);
    });
  }
}
