part of 'chat_controller.dart';

extension ChatControllerMessageFlags on ChatController {
  Future<bool> toggleSuppressEmbeds(ChatMessage message) async {
    final repository = _repository is MessageFlagRepository
        ? _repository as MessageFlagRepository
        : null;
    if (repository == null) return false;
    return _sendingIn(message.channelId, () async {
      final updated = await repository.setSuppressEmbeds(
        channelId: message.channelId,
        messageId: message.id,
        suppress: !message.suppressesEmbeds,
      );
      _workspace = _workspace?.upsertMessage(updated);
    });
  }
}
