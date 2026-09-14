part of 'mock_chat_repository.dart';

mixin _MockChatRepositoryMessageFlags implements MessageFlagRepository {
  ChatWorkspace get _workspace;
  set _workspace(ChatWorkspace value);
  StreamController<ChatRepositoryEvent> get _events;
  Future<void> _wait();

  @override
  Future<ChatMessage> setSuppressEmbeds({
    required String channelId,
    required String messageId,
    required bool suppress,
  }) async {
    await _wait();
    final current = _workspace.messages.firstWhere(
      (message) => message.id == messageId && message.channelId == channelId,
    );
    final flags = suppress
        ? current.flags | DiscordMessageFlag.suppressEmbeds.bit
        : current.flags & ~DiscordMessageFlag.suppressEmbeds.bit;
    final updated = current.copyWith(flags: flags);
    _workspace = _workspace.upsertMessage(updated);
    _events.add(MessageUpsertedEvent(message: updated));
    return updated;
  }
}
