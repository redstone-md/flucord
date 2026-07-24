part of 'chat_controller.dart';

extension ChatControllerMessageFlags on ChatController {
  Future<bool> toggleSuppressEmbeds(ChatMessage message) async {
    final repository = _repository is MessageFlagRepository
        ? _repository as MessageFlagRepository
        : null;
    if (repository == null || _isSending) return false;
    _isSending = true;
    _notify();
    try {
      final updated = await repository.setSuppressEmbeds(
        channelId: message.channelId,
        messageId: message.id,
        suppress: !message.suppressesEmbeds,
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
