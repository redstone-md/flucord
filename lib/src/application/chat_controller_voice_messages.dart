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
    if (workspace == null || repository == null) return false;
    return _sendingIn(channelId, () async {
      final message = await repository.sendVoiceMessage(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        voiceMessage: voiceMessage,
      );
      _applySentMessage(message);
    });
  }
}
