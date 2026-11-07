part of 'chat_controller.dart';

extension ChatControllerVoiceMessages on ChatController {
  /// Whether this session's transport can send voice messages at all.
  bool get canSendVoiceMessages => _repository is VoiceMessageRepository;

  /// Shows [voiceMessage] at once in the timeline and queues its send, the way
  /// a text message goes out. A failed one stays there with Retry and Delete.
  ///
  /// [onReleased] runs once the recording file is no longer needed: the
  /// message left the queue, or could not be queued at all.
  Future<bool> sendVoiceMessage({
    required String channelId,
    required PendingVoiceMessage voiceMessage,
    void Function()? onReleased,
  }) {
    final workspace = _workspace;
    if (!canSendVoiceMessages) {
      AppLog.warning(
        'chat.send',
        'Voice message not sent: ${_repository.runtimeType} cannot send '
            'voice messages',
      );
    }
    if (!canSendVoiceMessages || workspace == null) {
      onReleased?.call();
      return Future.value(false);
    }
    return _queueSend(
      OutgoingMessage(
        message: voiceMessage.asMessage(
          id: _outgoing.nextNonce(),
          channelId: channelId,
          authorId: workspace.currentMemberId,
          sentAt: DateTime.now(),
        ),
        kind: OutgoingVoice(voiceMessage),
      ),
      onLeave: onReleased,
    );
  }
}
