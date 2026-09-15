part of 'chat_controller_read_state_test.dart';

/// A direct conversation that arrived as a message request, in the DM space
/// the workspace keeps alongside the guild fixture.
void _messageRequestCases() {
  ChatWorkspace requestWorkspace(String channelLastMessageId) {
    final base = _workspace(channelLastMessageId);
    return base.copyWith(
      spaces: [...base.spaces, const CommunitySpace.directMessages()],
      channels: [
        ...base.channels,
        ConversationChannel(
          id: _requestId,
          spaceId: CommunitySpace.directMessagesId,
          name: 'mira',
          topic: '',
          kind: ChannelKind.text,
          recipientId: _authorId,
          lastMessageId: channelLastMessageId,
          isMessageRequest: true,
          messageRequestedAt: DateTime.utc(2026, 7, 1),
        ),
      ],
      messages: [
        ...base.messages,
        ChatMessage(
          id: _requestMessageId,
          channelId: _requestId,
          authorId: _authorId,
          body: 'is this thing on',
          sentAt: DateTime.utc(2026, 7, 25),
        ),
      ],
    );
  }

  _Repository requestRepository({required String channelLastMessageId}) {
    final repository = _Repository(channelLastMessageId: channelLastMessageId);
    // The real DM workspace carries the request channel, so the fake serves
    // the same shape the controller would read from the transport.
    repository.workspaceOverride = requestWorkspace(channelLastMessageId);
    return repository;
  }

  test(
    'accepting a request acks it and moves the conversation to the DM list',
    () async {
      final repository = requestRepository(channelLastMessageId: _newerMessage);
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _settle();

      expect(
        controller.workspace!.channelById(_requestId).isMessageRequest,
        isTrue,
      );
      expect(
        repository.readStateStore.messageRequestAcks,
        isEmpty,
        reason: 'nothing was answered yet',
      );

      await controller.acceptMessageRequest(_requestId);
      await _settle();

      final channel = controller.workspace!.channelById(_requestId);
      expect(channel.isMessageRequest, isFalse);
      expect(channel.messageRequestedAt, isNull);
      // The conversation is still present and still carries its history: the
      // answer moved it out of the request folder, not out of the account.
      expect(channel.recipientId, _authorId);
      expect(
        controller.workspace!.messagesFor(_requestId).single.body,
        'is this thing on',
      );
      // The ack is what Discord remembers so the request never returns.
      expect(repository.readStateStore.messageRequestAcks, [_requestId]);
    },
  );

  test('declining a request removes it and acks it', () async {
    final repository = requestRepository(channelLastMessageId: _newerMessage);
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await _settle();

    await controller.declineMessageRequest(_requestId);
    await _settle();

    expect(
      controller.workspace!.channelOrNull(_requestId),
      isNull,
      reason: 'a declined conversation leaves the workspace',
    );
    expect(repository.readStateStore.messageRequestAcks, [_requestId]);
  });

  test('a non-request channel answers neither action', () async {
    final repository = requestRepository(channelLastMessageId: _newerMessage);
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await _settle();

    await controller.acceptMessageRequest(_generalId);
    await controller.declineMessageRequest(_generalId);
    await _settle();

    expect(controller.workspace!.channelOrNull(_generalId), isNotNull);
    expect(repository.readStateStore.messageRequestAcks, isEmpty);
  });

  test(
    'the session-start collector deletes acked states older than 30 days',
    () async {
      final repository = requestRepository(channelLastMessageId: _newerMessage);
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _settle();

      // One load, one collector pass; the controller does not pass a clock, so
      // the pass ran with the repository's own now.
      expect(repository.readStateStore.garbageCollections, hasLength(1));
      expect(repository.readStateStore.garbageCollections.single, isNull);
    },
  );
}
