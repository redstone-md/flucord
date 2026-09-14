part of 'read_state_model_test.dart';

void _snapshotCases() {
  group('ReadStateSnapshot', () {
    test('answers with defaults for a space it has never heard of', () {
      final settings = ReadStateSnapshot.empty.settingsFor(_guildId);
      expect(settings.muted, isFalse);
      expect(settings.mobilePush, isTrue);
      expect(
        settings.messageNotifications,
        MessageNotificationLevel.allMessages,
      );
      expect(settings.version, -1);
      expect(ReadStateSnapshot.empty.forChannel(_channelId), isNull);
    });

    test('computes the identify snowflake cursors as string maxima', () {
      final snapshot = ReadStateSnapshot(
        readStates: {
          _channelId: ReadState(
            entityId: _channelId,
            lastAckedId: _newestMessage,
          ),
          _guildId: ReadState(entityId: _guildId, lastAckedId: _olderMessage),
          '1:$_guildId': ReadState(
            entityId: _guildId,
            type: ReadStateType.guildEvent,
            lastAckedId: _newerMessage,
          ),
          _categoryId: ReadState(entityId: _categoryId),
        },
      );

      expect(snapshot.highestLastMessageId, _newestMessage);
      expect(snapshot.privateChannelsVersion({_guildId}), _olderMessage);
      // The guild-event read state shares the guild id but is not a private
      // channel, so it must not leak into the private-channel maximum.
      expect(snapshot.privateChannelsVersion({_categoryId}), '0');
      expect(ReadStateSnapshot.empty.highestLastMessageId, '0');
      expect(ReadStateSnapshot.empty.privateChannelsVersion({_channelId}), '0');
    });

    test('resolves mute through the channel, its parent and the space', () {
      final now = DateTime.utc(2026, 7, 26, 12);
      final channel = _channel(id: _channelId, parentId: _categoryId);

      expect(
        ReadStateSnapshot.empty.isChannelMuted(channel, now: now),
        isFalse,
      );

      final channelMuted = _snapshotWith(
        GuildNotificationSettings(
          spaceId: _guildId,
          channelOverrides: {
            _channelId: const ChannelNotificationOverride(
              channelId: _channelId,
              muted: true,
            ),
          },
        ),
      );
      expect(channelMuted.isChannelMuted(channel, now: now), isTrue);

      final categoryMuted = _snapshotWith(
        GuildNotificationSettings(
          spaceId: _guildId,
          channelOverrides: {
            _categoryId: const ChannelNotificationOverride(
              channelId: _categoryId,
              muted: true,
            ),
          },
        ),
      );
      expect(categoryMuted.isChannelMuted(channel, now: now), isTrue);

      final spaceMuted = _snapshotWith(
        GuildNotificationSettings(spaceId: _guildId, muted: true),
      );
      expect(spaceMuted.isChannelMuted(channel, now: now), isTrue);
      expect(spaceMuted.isSpaceMuted(_guildId, now: now), isTrue);
      expect(spaceMuted.isSpaceMuted(_categoryId, now: now), isFalse);
    });

    test('lets a temporary mute lapse on the clock alone', () {
      final settings = GuildNotificationSettings(
        spaceId: _guildId,
        muted: true,
        muteConfig: NotificationMuteConfig(
          selectedTimeWindowSeconds: 3600,
          endTime: DateTime.utc(2026, 7, 26, 12),
        ),
      );
      final snapshot = _snapshotWith(settings);

      expect(
        snapshot.isSpaceMuted(_guildId, now: DateTime.utc(2026, 7, 26, 11)),
        isTrue,
      );
      expect(
        snapshot.isSpaceMuted(_guildId, now: DateTime.utc(2026, 7, 26, 13)),
        isFalse,
      );
      expect(settings.isMutedAt(DateTime.utc(2026, 7, 26, 13)), isFalse);
    });

    test('builds a mute config for a window and for always', () {
      final now = DateTime.utc(2026, 7, 26, 12);
      final hour = NotificationMuteConfig.forWindow(3600, now: now);
      expect(hour.endTime, DateTime.utc(2026, 7, 26, 13));
      expect(hour.isPermanent, isFalse);
      expect(hour.isActiveAt(DateTime.utc(2026, 7, 26, 12, 30)), isTrue);

      final always = NotificationMuteConfig.forWindow(
        NotificationMuteConfig.alwaysWindow,
        now: now,
      );
      expect(always.endTime, isNull);
      expect(always.isPermanent, isTrue);
      expect(always.isActiveAt(DateTime.utc(2030)), isTrue);
      expect(NotificationMuteConfig.presetWindows, contains(-1));
    });

    test('resolves the notification level channel, parent, then guild', () {
      final channel = _channel(id: _channelId, parentId: _categoryId);
      expect(
        ReadStateSnapshot.empty.notificationLevelFor(channel),
        MessageNotificationLevel.allMessages,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            messageNotifications: MessageNotificationLevel.noMessages,
            channelOverrides: {
              _categoryId: const ChannelNotificationOverride(
                channelId: _categoryId,
                messageNotifications: MessageNotificationLevel.onlyMentions,
              ),
              _channelId: const ChannelNotificationOverride(
                channelId: _channelId,
                messageNotifications: MessageNotificationLevel.allMessages,
              ),
            },
          ),
        ).notificationLevelFor(channel),
        MessageNotificationLevel.allMessages,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            messageNotifications: MessageNotificationLevel.noMessages,
            channelOverrides: {
              _categoryId: const ChannelNotificationOverride(
                channelId: _categoryId,
                messageNotifications: MessageNotificationLevel.onlyMentions,
              ),
              _channelId: const ChannelNotificationOverride(
                channelId: _channelId,
              ),
            },
          ),
        ).notificationLevelFor(channel),
        MessageNotificationLevel.onlyMentions,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            messageNotifications: MessageNotificationLevel.noMessages,
          ),
        ).notificationLevelFor(channel),
        MessageNotificationLevel.noMessages,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            messageNotifications: MessageNotificationLevel.inherit,
          ),
        ).notificationLevelFor(channel),
        MessageNotificationLevel.allMessages,
      );
    });

    test('short-circuits the unread badge without USE_NEW_NOTIFICATIONS', () {
      final channel = _channel(id: _channelId);
      final snapshot = _snapshotWith(
        GuildNotificationSettings(
          spaceId: _guildId,
          flags: GuildNotificationFlags.unreadsOnlyMentions,
        ),
      );
      expect(snapshot.usesNewNotifications, isFalse);
      expect(snapshot.unreadBadgeFor(channel), UnreadBadge.allMessages);
    });

    test('resolves the unread badge through the flag chain', () {
      final channel = _channel(id: _channelId, parentId: _categoryId);

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            flags: GuildNotificationFlags.unreadsOnlyMentions,
          ),
          accountFlags: AccountNotificationFlags.useNewNotifications,
        ).unreadBadgeFor(channel),
        UnreadBadge.onlyMentions,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            flags: GuildNotificationFlags.unreadsAllMessages,
          ),
          accountFlags: AccountNotificationFlags.useNewNotifications,
        ).unreadBadgeFor(channel),
        UnreadBadge.allMessages,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            flags: GuildNotificationFlags.unreadsAllMessages,
            channelOverrides: {
              _categoryId: const ChannelNotificationOverride(
                channelId: _categoryId,
                flags: ChannelOverrideFlags.unreadsOnlyMentions,
              ),
            },
          ),
          accountFlags: AccountNotificationFlags.useNewNotifications,
        ).unreadBadgeFor(channel),
        UnreadBadge.onlyMentions,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            channelOverrides: {
              _channelId: const ChannelNotificationOverride(
                channelId: _channelId,
                flags: ChannelOverrideFlags.unreadsAllMessages,
              ),
            },
          ),
          accountFlags: AccountNotificationFlags.useNewNotifications,
        ).unreadBadgeFor(channel),
        UnreadBadge.allMessages,
      );

      // No flag anywhere falls back to the resolved notification level.
      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            messageNotifications: MessageNotificationLevel.onlyMentions,
          ),
          accountFlags: AccountNotificationFlags.useNewNotifications,
        ).unreadBadgeFor(channel),
        UnreadBadge.onlyMentions,
      );
    });

    test('gates desktop notifications on mute, level and suppress', () {
      final channel = _channel(id: _channelId);

      expect(
        ReadStateSnapshot.empty.allowsDesktopNotification(
          channel,
          mentionsCurrentMember: false,
        ),
        isTrue,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(spaceId: _guildId, muted: true),
        ).allowsDesktopNotification(channel, mentionsCurrentMember: true),
        isFalse,
      );

      final mentionsOnly = _snapshotWith(
        GuildNotificationSettings(
          spaceId: _guildId,
          messageNotifications: MessageNotificationLevel.onlyMentions,
        ),
      );
      expect(
        mentionsOnly.allowsDesktopNotification(
          channel,
          mentionsCurrentMember: false,
        ),
        isFalse,
      );
      expect(
        mentionsOnly.allowsDesktopNotification(
          channel,
          mentionsCurrentMember: true,
        ),
        isTrue,
      );
      expect(
        mentionsOnly.allowsDesktopNotification(
          channel,
          mentionsCurrentMember: false,
          mentionsEveryone: true,
        ),
        isTrue,
      );

      final suppressed = _snapshotWith(
        GuildNotificationSettings(
          spaceId: _guildId,
          messageNotifications: MessageNotificationLevel.onlyMentions,
          suppressEveryone: true,
        ),
      );
      expect(
        suppressed.allowsDesktopNotification(
          channel,
          mentionsCurrentMember: false,
          mentionsEveryone: true,
        ),
        isFalse,
      );
      expect(
        suppressed.allowsDesktopNotification(
          channel,
          mentionsCurrentMember: true,
          mentionsEveryone: true,
        ),
        isTrue,
      );

      expect(
        _snapshotWith(
          GuildNotificationSettings(
            spaceId: _guildId,
            messageNotifications: MessageNotificationLevel.noMessages,
          ),
        ).allowsDesktopNotification(channel, mentionsCurrentMember: true),
        isFalse,
      );
    });

    test('copyWith replaces only what it is given', () {
      final snapshot = ReadStateSnapshot(
        readStates: {_channelId: ReadState(entityId: _channelId)},
        readStateVersion: 4,
        userGuildSettingsVersion: 9,
        accountNotificationFlags: 16,
      );
      final next = snapshot.copyWith(readStateVersion: 5);
      expect(next.readStateVersion, 5);
      expect(next.userGuildSettingsVersion, 9);
      expect(next.accountNotificationFlags, 16);
      expect(next.readStates.keys, [_channelId]);
      expect(
        snapshot
            .copyWith(
              readStates: const {},
              settings: const {},
              userGuildSettingsVersion: 11,
              accountNotificationFlags: 32,
            )
            .userGuildSettingsVersion,
        11,
      );
    });
  });
}
