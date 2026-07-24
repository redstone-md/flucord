part of 'chat_controller.dart';

extension ChatControllerVoiceMessages on ChatController {
  Future<bool> sendVoiceMessage({
    required String channelId,
    required PendingVoiceMessage voiceMessage,
  }) async {
    final workspace = _workspace;
    final repository = _repository is VoiceMessageRepository
        ? _repository as VoiceMessageRepository
        : null;
    if (workspace == null || repository == null || _isSending) return false;
    _isSending = true;
    _notify();
    try {
      final message = await repository.sendVoiceMessage(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        voiceMessage: voiceMessage,
      );
      _workspace = _workspace?.upsertMessage(message);
      _workspace = _workspace?.clearChannelUnreadBoundary(channelId);
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
}
