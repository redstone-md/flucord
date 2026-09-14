part of 'read_state_model_test.dart';

void _projectionCases() {
  group('ReadStateProjection', () {
    test('leaves a channel the server holds no read state for alone', () {
      final workspace = _workspace().markChannelUnread(
        _channelId,
        messageId: _newerMessage,
        mention: true,
      );
      final projected = workspace.applyReadState(ReadStateSnapshot.empty);
      expect(projected.channelById(_channelId).unread, isTrue);
      expect(projected.channelById(_channelId).mentionCount, 1);
    });

    test('replaces local unread with the server answer', () {
      final workspace = _workspace().markChannelUnread(
        _channelId,
        messageId: _newerMessage,
        mention: true,
      );
      final projected = workspace.applyReadState(
        ReadStateSnapshot(
          readStates: {
            _channelId: ReadState(
              entityId: _channelId,
              lastAckedId: _newestMessage,
              mentionCount: 0,
            ),
          },
        ),
      );

      final channel = projected.channelById(_channelId);
      expect(channel.unread, isFalse);
      expect(channel.mentionCount, 0);
      expect(channel.firstUnreadMessageId, isNull);
    });

    test('derives the NEW divider from the ack cursor', () {
      final projected = _workspace().applyReadState(
        ReadStateSnapshot(
          readStates: {
            _channelId: ReadState(
              entityId: _channelId,
              lastAckedId: _olderMessage,
              mentionCount: 2,
            ),
          },
        ),
      );

      final channel = projected.channelById(_channelId);
      expect(channel.unread, isTrue);
      expect(channel.mentionCount, 2);
      expect(channel.firstUnreadMessageId, _newerMessage);
    });

    test('marks a never-acked channel unread without a cached boundary', () {
      final workspace = ChatWorkspace(
        spaces: _workspace().spaces,
        channels: _workspace().channels,
        members: _workspace().members,
        messages: const [],
        currentMemberId: _workspace().currentMemberId,
      );
      final projected = workspace.applyReadState(
        ReadStateSnapshot(
          readStates: {_channelId: ReadState(entityId: _channelId)},
        ),
      );
      expect(projected.channelById(_channelId).unread, isTrue);
      expect(projected.channelById(_channelId).firstUnreadMessageId, isNull);
    });
  });

  group('ConversationChannel.withLatestMessage', () {
    test('never rewinds the pointer', () {
      const channel = ConversationChannel(
        id: _channelId,
        spaceId: _guildId,
        name: 'general',
        topic: '',
        kind: ChannelKind.text,
      );
      final advanced = channel.withLatestMessage(_newerMessage);
      expect(advanced.lastMessageId, _newerMessage);
      expect(
        identical(advanced.withLatestMessage(_olderMessage), advanced),
        isTrue,
      );
      expect(
        advanced.withLatestMessage(_newestMessage).lastMessageId,
        _newestMessage,
      );
    });

    test('keeps a remembered pointer through a pointerless update', () {
      const previous = ConversationChannel(
        id: _channelId,
        spaceId: _guildId,
        name: 'general',
        topic: '',
        kind: ChannelKind.text,
        lastMessageId: _newerMessage,
        unread: true,
        mentionCount: 2,
      );
      const incoming = ConversationChannel(
        id: _channelId,
        spaceId: _guildId,
        name: 'renamed',
        topic: '',
        kind: ChannelKind.text,
      );
      final merged = incoming.withActivityOf(previous);
      expect(merged.name, 'renamed');
      expect(merged.lastMessageId, _newerMessage);
      expect(merged.mentionCount, 2);
    });
  });
}
