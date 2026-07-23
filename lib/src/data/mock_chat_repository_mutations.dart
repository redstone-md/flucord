part of 'mock_chat_repository.dart';

extension _MockChatRepositoryMutations on MockChatRepository {
  Future<void> _setReaction(
    String messageId,
    String emoji, {
    required bool add,
  }) async {
    await _wait();
    final message = _workspace.messages.firstWhere(
      (candidate) => candidate.id == messageId,
    );
    final reactions = [...message.reactions];
    final index = reactions.indexWhere((reaction) => reaction.key == emoji);
    if (index < 0 && add) {
      reactions.add(
        MessageReaction(emojiName: emoji, count: 1, reactedByCurrentUser: true),
      );
    } else if (index >= 0) {
      final current = reactions[index];
      final count = add ? current.count + 1 : current.count - 1;
      if (count <= 0) {
        reactions.removeAt(index);
      } else {
        reactions[index] = current.copyWith(
          count: count,
          reactedByCurrentUser: add,
        );
      }
    }
    final updated = message.copyWith(reactions: reactions);
    _workspace = _workspace.upsertMessage(updated);
    _events.add(MessageUpsertedEvent(message: updated));
  }
}
