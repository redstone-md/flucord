part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryForwards implements MessageForwardRepository {
  ChatWorkspace get _workspace;
  set _workspace(ChatWorkspace value);
  int get _messageSequence;
  set _messageSequence(int value);
  StreamController<ChatRepositoryEvent> get _events;
  Future<void> _wait();

  @override
  Future<ChatMessage> forwardMessage({
    required String sourceChannelId,
    required String sourceMessageId,
    required String targetChannelId,
  }) async {
    await _wait();
    final source = _workspace.messages.firstWhere(
      (message) =>
          message.id == sourceMessageId && message.channelId == sourceChannelId,
    );
    if (!source.canForward) throw StateError('Message cannot be forwarded');
    final sourceChannel = _workspace.channelById(sourceChannelId);
    final sourceSpace = _workspace.spaceById(sourceChannel.spaceId);
    final message = ChatMessage(
      id: 'mock-forward-${_messageSequence++}',
      channelId: targetChannelId,
      authorId: _workspace.currentMemberId,
      body: '',
      sentAt: DateTime.now(),
      reference: MessageReference(
        type: DiscordMessageReferenceType.forward,
        messageId: source.id,
        channelId: source.channelId,
        guildId: sourceSpace.isDirectMessages ? null : sourceSpace.id,
      ),
      snapshots: [
        MessageSnapshot(
          type: source.type,
          body: source.body,
          sentAt: source.sentAt,
          editedAt: source.isEdited ? source.sentAt : null,
          attachments: source.attachments,
          embeds: source.embeds,
          stickers: source.stickers,
        ),
      ],
    );
    _workspace = _workspace.upsertMessage(message);
    _events.add(MessageUpsertedEvent(message: message));
    return message;
  }
}
