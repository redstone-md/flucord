part of 'mock_chat_repository.dart';

extension _MockChatRepositoryMutations on MockChatRepository {
  Future<ArchivedThreadPage> _loadArchivedThreadPage(
    String parentChannelId, {
    DateTime? before,
  }) async {
    await _wait();
    final parent = _workspace.channelById(parentChannelId);
    final page = before == null ? 1 : 2;
    ConversationChannel archivedThread(int index) => ConversationChannel(
      id: 'archived-$parentChannelId-$index',
      spaceId: parent.spaceId,
      name: index == 1 ? 'release-retrospective' : 'transport-notes',
      topic: '',
      kind: ChannelKind.text,
      parentId: parent.id,
      isThread: true,
      isArchived: true,
      isLocked: index == 2,
      archiveTimestamp: DateTime.utc(2026, 7, 23 - index, 1, 30),
      autoArchiveDurationMinutes: 1440,
    );

    final threads = [archivedThread(1), if (page == 2) archivedThread(2)];
    for (final thread in threads) {
      _workspace = _workspace.upsertChannel(thread);
    }
    return ArchivedThreadPage(
      threads: threads,
      hasMore: page == 1,
      nextBefore: threads.last.archiveTimestamp,
    );
  }

  Future<void> _setPinned(String messageId, bool pinned) async {
    await _wait();
    final message = _workspace.messages.firstWhere(
      (candidate) => candidate.id == messageId,
    );
    final updated = message.copyWith(isPinned: pinned);
    _workspace = _workspace.upsertMessage(updated);
    _events.add(MessageUpsertedEvent(message: updated));
    _events.add(PinsChangedEvent(message.channelId));
  }

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
