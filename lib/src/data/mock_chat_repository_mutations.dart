part of 'mock_chat_repository.dart';

extension _MockChatRepositoryMutations on MockChatRepository {
  Future<ConversationChannel> _createMessageThread({
    required String channelId,
    required String messageId,
    required String name,
  }) async {
    await _wait();
    final parent = _workspace.channelById(channelId);
    final thread = ConversationChannel(
      id: messageId,
      spaceId: parent.spaceId,
      name: name.trim(),
      topic: '',
      kind: ChannelKind.text,
      position: parent.position,
      parentId: parent.id,
      isThread: true,
    );
    _workspace = _workspace.upsertChannel(thread);
    _events.add(ChannelUpsertedEvent(thread));
    return thread;
  }

  Future<CreatedForumPost> _createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    required List<PendingAttachment> attachments,
    required List<String> appliedTagIds,
  }) async {
    await _wait();
    final parent = _workspace.channelById(channelId);
    final id = 'forum-post-${_messageSequence++}';
    final thread = ConversationChannel(
      id: id,
      spaceId: parent.spaceId,
      name: name.trim(),
      topic: '',
      kind: ChannelKind.text,
      position: parent.position,
      parentId: parent.id,
      isThread: true,
      appliedTagIds: List.unmodifiable(appliedTagIds),
      autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    );
    final message = ChatMessage(
      id: '$id-starter',
      channelId: id,
      authorId: _workspace.currentMemberId,
      body: content.trim(),
      sentAt: DateTime.now(),
      attachments: [
        for (var index = 0; index < attachments.length; index++)
          MessageAttachment(
            id: '$id-attachment-$index',
            fileName: attachments[index].name,
            url: Uri.file(attachments[index].path).toString(),
            size: attachments[index].size,
          ),
      ],
    );
    _workspace = _workspace.upsertChannel(thread).upsertMessage(message);
    _events.add(ChannelUpsertedEvent(thread));
    _events.add(MessageUpsertedEvent(message: message));
    return CreatedForumPost(thread: thread, initialMessage: message);
  }

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
      final starter = ChatMessage(
        id: '${thread.id}-starter',
        channelId: thread.id,
        authorId: _workspace.currentMemberId,
        body: 'Preview for ${thread.name}.',
        sentAt: thread.archiveTimestamp ?? DateTime.now(),
      );
      _workspace = _workspace.upsertChannel(thread).upsertMessage(starter);
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
