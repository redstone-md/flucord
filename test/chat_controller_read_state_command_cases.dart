part of 'chat_controller_read_state_test.dart';

void _commandCases() {
  test('mark-all-read expands into one pass per space', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    repository.readStateStore.publish(
      ReadStateSnapshot(
        readStates: {
          _generalId: ReadState(entityId: _generalId, mentionCount: 2),
        },
      ),
    );
    await _settle();

    controller.markAllChannelsRead();
    await _settle();

    // Only the channel the account may view is offered up.
    expect(
      repository.readStateStore.spaceReads.map(
        (entry) => '${entry.$1}:${entry.$2.join(',')}',
      ),
      ['$_guildId:$_generalId'],
    );
  });

  test('marks unread from the message before the chosen one', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    final message = controller.workspace!
        .messagesFor(_generalId)
        .firstWhere((item) => item.id == _newerMessage);
    await controller.markChannelUnreadFrom(message);

    expect(repository.readStateStore.unread, [(_generalId, _olderMessage, 0)]);
  });

  test('synthesises an id when nothing older is cached', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    final message = controller.workspace!
        .messagesFor(_generalId)
        .firstWhere((item) => item.id == _olderMessage);
    await controller.markChannelUnreadFrom(message);

    final recorded = repository.readStateStore.unread.single;
    expect(recorded.$2, isNot(_olderMessage));
    expect(int.parse(recorded.$2), greaterThan(0));
  });

  test('routes every notification edit to the read-state store', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    final channel = controller.workspace!.channelById(_generalId);

    await controller.setChannelMuted(channel, muted: true, windowSeconds: 3600);
    await controller.setChannelMuted(channel, muted: false);
    await controller.setChannelNotificationLevel(
      channel,
      MessageNotificationLevel.onlyMentions,
    );
    await controller.setSpaceMuted(_guildId, muted: true, windowSeconds: 900);
    await controller.setSpaceNotificationLevel(
      _guildId,
      MessageNotificationLevel.noMessages,
    );
    await controller.setSpaceSuppressEveryone(_guildId, true);
    await controller.setSpaceSuppressRoles(_guildId, true);
    await controller.setSpaceMobilePush(_guildId, false);

    final overrides = repository.readStateStore.overrides;
    expect(overrides, hasLength(3));
    expect(overrides.first.$3.muted, isTrue);
    expect(overrides.first.$3.muteConfig!.selectedTimeWindowSeconds, 3600);
    expect(overrides[1].$3.muted, isFalse);
    expect(overrides[1].$3.clearMuteConfig, isTrue);
    expect(
      overrides.last.$3.messageNotifications,
      MessageNotificationLevel.onlyMentions,
    );

    final patches = repository.readStateStore.spacePatches;
    expect(patches, hasLength(5));
    expect(patches.first.$2.muted, isTrue);
    expect(patches.first.$2.clearMuteConfig, isFalse);
    expect(patches.first.$2.muteConfig!.selectedTimeWindowSeconds, 900);
    expect(
      patches[1].$2.messageNotifications,
      MessageNotificationLevel.noMessages,
    );
    expect(patches[2].$2.suppressEveryone, isTrue);
    expect(patches[3].$2.suppressRoles, isTrue);
    expect(patches.last.$2.mobilePush, isFalse);
  });

  test('a failing read-state call never becomes a controller error', () async {
    final repository = _Repository(failing: true);
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    final channel = controller.workspace!.channelById(_generalId);

    await controller.setSpaceMuted(_guildId, muted: true);
    await controller.setChannelMuted(channel, muted: true);
    await controller.markSpaceRead(_guildId);
    await controller.markChannelUnreadFrom(
      controller.workspace!.messagesFor(_generalId).last,
    );

    expect(controller.error, isNull);
  });

  test(
    'a transport with no read state answers with the empty snapshot',
    () async {
      final repository = _Repository(withReadState: false);
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      final channel = controller.workspace!.channelById(_generalId);

      expect(controller.readStateRepository, isNull);
      expect(controller.readState.readStates, isEmpty);
      expect(controller.isChannelMuted(channel), isFalse);
      expect(controller.isSpaceMuted(_guildId), isFalse);
      controller.acknowledgeChannel(_generalId);
      await controller.markSpaceRead(_guildId);
      await controller.setSpaceMuted(_guildId, muted: true);
      await controller.setChannelMuted(channel, muted: true);
      await controller.markChannelUnreadFrom(
        controller.workspace!.messagesFor(_generalId).last,
      );
      expect(controller.error, isNull);
    },
  );

  test('the unread pip follows the resolved badge setting', () async {
    final repository = _Repository();
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    repository.readStateStore.publish(
      ReadStateSnapshot(
        accountNotificationFlags: AccountNotificationFlags.useNewNotifications,
        readStates: {
          _generalId: ReadState(
            entityId: _generalId,
            lastAckedId: _olderMessage,
          ),
        },
        settings: {
          _guildId: GuildNotificationSettings(
            spaceId: _guildId,
            flags: GuildNotificationFlags.unreadsOnlyMentions,
          ),
        },
      ),
    );
    await _settle();

    final channel = controller.workspace!.channelById(_generalId);
    expect(channel.unread, isTrue);
    expect(controller.showsUnreadFor(channel), isFalse);
    expect(
      controller.showsUnreadFor(channel.copyWith(mentionCount: 1)),
      isTrue,
    );
    expect(controller.showsUnreadFor(channel.copyWith(unread: false)), isFalse);
  });
}
