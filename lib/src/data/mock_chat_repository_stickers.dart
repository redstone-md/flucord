part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryStickers implements StickerRepository {
  ChatWorkspace get _workspace;
  set _workspace(ChatWorkspace value);
  int get _messageSequence;
  set _messageSequence(int value);
  Future<void> _wait();

  @override
  Future<ChatMessage> sendStickers({
    required String channelId,
    required String authorId,
    required List<String> stickerIds,
  }) async {
    await _wait();
    final channel = _workspace.channelById(channelId);
    final catalog = {
      for (final sticker in _workspace.stickersFor(channel.spaceId))
        sticker.id: sticker.item,
    };
    final message = ChatMessage(
      id: 'local-${_messageSequence++}',
      channelId: channelId,
      authorId: authorId,
      body: '',
      sentAt: DateTime.now(),
      stickers: [for (final id in stickerIds) catalog[id]!],
    );
    _workspace = _workspace.upsertMessage(message);
    return message;
  }
}
