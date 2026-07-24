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
  }) async {
    await _wait();
    final messageId = 'local-${_messageSequence++}';
    final message = ChatMessage(
      id: messageId,
      channelId: channelId,
      authorId: authorId,
      body: '',
      sentAt: DateTime.now(),
      flags: DiscordMessageFlag.voiceMessage.bit,
      attachments: [
        MessageAttachment(
          id: '$messageId-voice',
          fileName: voiceMessage.name,
          url: Uri.file(voiceMessage.path).toString(),
          size: voiceMessage.size,
          contentType: 'audio/ogg',
          durationSecs: voiceMessage.durationSecs,
          waveform: voiceMessage.waveform,
        ),
      ],
    );
    _workspace = _workspace.upsertMessage(message);
    return message;
  }
}
