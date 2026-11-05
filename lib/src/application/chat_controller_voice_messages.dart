part of 'chat_controller.dart';

extension ChatControllerVoiceMessages on ChatController {
  /// Whether this session's transport can send voice messages at all.
  bool get canSendVoiceMessages => _repository is VoiceMessageRepository;

  Future<bool> sendVoiceMessage({
    required String channelId,
    required PendingVoiceMessage voiceMessage,
  }) async {
    final workspace = _workspace;
    if (_repository is! VoiceMessageRepository) {
      AppLog.warning(
        'chat.send',
        'Voice message not sent: ${_repository.runtimeType} cannot send '
            'voice messages',
      );
      return false;
    }
    final repository = _repository as VoiceMessageRepository;
    if (workspace == null) return false;
    return _sendingIn(channelId, what: 'voice message', () async {
      final message = await repository.sendVoiceMessage(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        voiceMessage: voiceMessage,
      );
      _applySentMessage(message);
    });
  }
}
