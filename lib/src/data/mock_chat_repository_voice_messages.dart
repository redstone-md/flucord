part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryVoiceMessages implements VoiceMessageRepository {
  ChatWorkspace get _workspace;
  set _workspace(ChatWorkspace value);
  int get _messageSequence;
  set _messageSequence(int value);
  Future<void> _wait();

  @override
  Future<ChatMessage> sendVoiceMessage({
    required String channelId,
    required String authorId,
    required PendingVoiceMessage voiceMessage,
    required String nonce,
    UploadProgressListener? onUploadProgress,
  }) async {
    await _wait();
    final message = voiceMessage.asMessage(
      id: 'local-${_messageSequence++}',
      channelId: channelId,
      authorId: authorId,
      sentAt: DateTime.now(),
    );
    _workspace = _workspace.upsertMessage(message);
    return message;
  }
}
