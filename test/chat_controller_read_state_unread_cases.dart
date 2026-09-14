part of 'chat_controller_read_state_test.dart';

void _unreadCases() {
  test('server read state replaces the local unread answer', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    repository.readStateStore.publish(
      ReadStateSnapshot(
        readStates: {
          _generalId: ReadState(
            entityId: _generalId,
            lastAckedId: _olderMessage,
            mentionCount: 4,
          ),
        },
      ),
    );
    await _settle();

    final channel = controller.workspace!.channelById(_generalId);
    expect(channel.unread, isTrue);
    expect(channel.mentionCount, 4);
    expect(channel.firstUnreadMessageId, _newerMessage);
  });

  test('a message in a channel nobody is watching goes unread', () async {
    final repository = _Repository(channelLastMessageId: _olderMessage);
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    repository.readStateStore.publish(
      ReadStateSnapshot(
        readStates: {
          _generalId: ReadState(
            entityId: _generalId,
            lastAckedId: _olderMessage,
          ),
        },
      ),
    );
    await _settle();
    expect(controller.workspace!.channelById(_generalId).unread, isFalse);
    controller.setApplicationActive(false);

    repository.emit(
      MessageUpsertedEvent(
        message: ChatMessage(
          id: _newerMessage,
          channelId: _generalId,
          authorId: _authorId,
          body: 'later',
          sentAt: DateTime.utc(2026, 7, 26),
        ),
        isNew: true,
      ),
    );
    await _settle();

    expect(controller.workspace!.channelById(_generalId).unread, isTrue);
  });

  test('opening a channel acknowledges its newest message', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    repository.readStateStore.acknowledged.clear();

    await controller.openChannel(_generalId);
    await _settle();

    expect(
      repository.readStateStore.acknowledged,
      contains((_generalId, _newerMessage)),
    );
  });

  test('refuses to acknowledge a channel the account cannot view', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await _settle();
    repository.readStateStore.acknowledged.clear();

    controller.acknowledgeChannel(_hiddenId);
    await _settle();

    expect(repository.readStateStore.acknowledged, isEmpty);
  });

  test('window focus acknowledges the channel on screen', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.openChannel(_generalId);
    repository.readStateStore.acknowledged.clear();

    controller
      ..setApplicationActive(false)
      ..setApplicationActive(true);
    await _settle();

    expect(repository.readStateStore.acknowledged, isNotEmpty);
  });

  test(
    'a passive last-message update makes the channel unread again',
    () async {
      final repository = _Repository(channelLastMessageId: _olderMessage);
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      repository.readStateStore.publish(
        ReadStateSnapshot(
          readStates: {
            _generalId: ReadState(
              entityId: _generalId,
              lastAckedId: _olderMessage,
            ),
          },
        ),
      );
      await _settle();
      expect(controller.workspace!.channelById(_generalId).unread, isFalse);

      repository.emit(
        const ChannelLastMessageEvent(
          channelId: _generalId,
          messageId: _newerMessage,
        ),
      );
      await _settle();

      expect(controller.workspace!.channelById(_generalId).unread, isTrue);
    },
  );
}
