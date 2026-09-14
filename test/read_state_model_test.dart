import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_snowflake.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flutter_test/flutter_test.dart';

part 'read_state_model_projection_cases.dart';
part 'read_state_model_snapshot_cases.dart';

const _guildId = '111111111111111111';
const _channelId = '222222222222222222';
const _categoryId = '333333333333333333';
const _olderMessage = '123456789012345678';
const _newerMessage = '234567890123456789';
const _newestMessage = '987654321098765432';

void main() {
  group('ReadStateType', () {
    test('defaults an absent type to CHANNEL and rejects unknown numbers', () {
      expect(ReadStateType.fromWire(null), ReadStateType.channel);
      expect(ReadStateType.fromWire(0), ReadStateType.channel);
      expect(ReadStateType.fromWire(5), ReadStateType.messageRequests);
      expect(ReadStateType.fromWire(6), isNull);
      expect(ReadStateType.fromWire('1'), isNull);
    });

    test('splits the two non-channel ack scopes', () {
      expect(ReadStateType.guildEvent.isGuildScoped, isTrue);
      expect(ReadStateType.guildHome.isGuildScoped, isTrue);
      expect(ReadStateType.guildOnboardingQuestion.isGuildScoped, isTrue);
      expect(ReadStateType.guildEvent.isUserScoped, isFalse);
      expect(ReadStateType.notificationCenter.isUserScoped, isTrue);
      expect(ReadStateType.messageRequests.isUserScoped, isTrue);
      expect(ReadStateType.channel.isGuildScoped, isFalse);
      expect(ReadStateType.channel.isUserScoped, isFalse);
    });
  });

  group('ReadState', () {
    test('treats zero, empty and null cursors as never acknowledged', () {
      expect(ReadState(entityId: _channelId).lastAckedId, isNull);
      expect(
        ReadState(entityId: _channelId, lastAckedId: '0').lastAckedId,
        isNull,
      );
      expect(
        ReadState(entityId: _channelId, lastAckedId: '').lastAckedId,
        isNull,
      );
      expect(
        ReadState(entityId: _channelId, lastAckedId: '00').lastAckedId,
        isNull,
      );
      expect(ReadState(entityId: _channelId).isBehind(_olderMessage), isTrue);
    });

    test('clamps a negative badge count', () {
      expect(ReadState(entityId: _channelId, mentionCount: -3).mentionCount, 0);
      expect(
        ReadState(entityId: _channelId, mentionCount: 2).hasMentions,
        isTrue,
      );
    });

    test('compares the cursor as a snowflake, not a number', () {
      final state = ReadState(entityId: _channelId, lastAckedId: _olderMessage);
      expect(state.isBehind(_newerMessage), isTrue);
      expect(state.isBehind(_olderMessage), isFalse);
      expect(state.isBehind(null), isFalse);
      expect(state.isBehind(''), isFalse);
    });

    test('refuses to rewind on acknowledgement but still records the day', () {
      final state = ReadState(
        entityId: _channelId,
        lastAckedId: _newerMessage,
        mentionCount: 4,
        lastViewed: 10,
      );

      final backwards = state.acknowledged(_olderMessage);
      expect(backwards.lastAckedId, _newerMessage);
      expect(backwards.mentionCount, 4);
      expect(identical(backwards, state), isTrue);

      final sameDay = state.acknowledged(_olderMessage, lastViewed: 10);
      expect(identical(sameDay, state), isTrue);

      final newDay = state.acknowledged(_olderMessage, lastViewed: 11);
      expect(newDay.lastAckedId, _newerMessage);
      expect(newDay.lastViewed, 11);
      expect(newDay.mentionCount, 4);

      final forwards = state.acknowledged(_newestMessage, lastViewed: 12);
      expect(forwards.lastAckedId, _newestMessage);
      expect(forwards.mentionCount, 0);
      expect(forwards.lastViewed, 12);
    });

    test('acknowledges from nothing', () {
      final state = ReadState(entityId: _channelId).acknowledged(_olderMessage);
      expect(state.lastAckedId, _olderMessage);
      expect(state.lastViewed, isNull);
    });

    test('keys channel states bare and namespaces every other type', () {
      expect(ReadState(entityId: _channelId).key, _channelId);
      expect(
        ReadState(entityId: _guildId, type: ReadStateType.guildEvent).key,
        '1:$_guildId',
      );
      expect(
        ReadState.keyFor(ReadStateType.messageRequests, _guildId),
        '5:$_guildId',
      );
    });

    test('copyWith keeps unnamed fields and can clear the nullable ones', () {
      final pinned = DateTime.utc(2026, 7, 20);
      final state = ReadState(
        entityId: _channelId,
        lastAckedId: _olderMessage,
        mentionCount: 3,
        flags:
            ReadStateFlags.guildChannel | ReadStateFlags.mentionLowImportance,
        lastViewed: 7,
        lastPinTimestamp: pinned,
      );

      final kept = state.copyWith();
      expect(kept.lastAckedId, _olderMessage);
      expect(kept.mentionCount, 3);
      expect(kept.lastViewed, 7);
      expect(kept.lastPinTimestamp, pinned);
      expect(kept.isMentionLowImportance, isTrue);

      final cleared = state.copyWith(
        type: ReadStateType.channel,
        lastAckedId: null,
        flags: 0,
        lastViewed: null,
        lastPinTimestamp: null,
      );
      expect(cleared.lastAckedId, isNull);
      expect(cleared.lastViewed, isNull);
      expect(cleared.lastPinTimestamp, isNull);
      expect(cleared.isMentionLowImportance, isFalse);
    });
  });

  group('ReadStateFlags', () {
    test('reproduces the thread / guild channel / DM computation', () {
      expect(
        ReadStateFlags.forChannel(_channel(id: _channelId, isThread: true)),
        ReadStateFlags.thread,
      );
      expect(
        ReadStateFlags.forChannel(_channel(id: _channelId)),
        ReadStateFlags.guildChannel,
      );
      expect(
        ReadStateFlags.forChannel(
          _channel(id: _channelId, spaceId: CommunitySpace.directMessagesId),
        ),
        0,
      );
    });
  });

  group('readStateLastViewedFor', () {
    test('rounds whole days up from the Discord epoch', () {
      final epoch = DateTime.fromMillisecondsSinceEpoch(
        DiscordSnowflake.epochMillis,
        isUtc: true,
      );
      expect(readStateLastViewedFor(epoch), 0);
      expect(
        readStateLastViewedFor(epoch.subtract(const Duration(days: 1))),
        0,
      );
      expect(readStateLastViewedFor(epoch.add(const Duration(hours: 1))), 1);
      expect(readStateLastViewedFor(epoch.add(const Duration(days: 1))), 1);
      expect(
        readStateLastViewedFor(
          epoch.add(const Duration(days: 1, milliseconds: 1)),
        ),
        2,
      );
    });
  });

  _snapshotCases();

  group('GuildNotificationSettings', () {
    test('withOverride adds and removes a single channel entry', () {
      final settings = GuildNotificationSettings(spaceId: _guildId);
      final added = settings.withOverride(
        _channelId,
        const ChannelNotificationOverride(channelId: _channelId, muted: true),
      );
      expect(added.overrideFor(_channelId)?.muted, isTrue);
      expect(added.overrideFor(null), isNull);
      expect(added.withOverride(_channelId, null).channelOverrides, isEmpty);
      expect(settings.isDirectMessages, isFalse);
      expect(
        GuildNotificationSettings.defaults(
          CommunitySpace.directMessagesId,
        ).isDirectMessages,
        isTrue,
      );
    });

    test('copyWith can clear the mute config independently of muted', () {
      final settings = GuildNotificationSettings(
        spaceId: _guildId,
        muted: true,
        muteConfig: const NotificationMuteConfig(
          selectedTimeWindowSeconds: 900,
        ),
        notifyHighlights: NotifyHighlights.enabled,
        hideMutedChannels: true,
        suppressRoles: true,
        muteScheduledEvents: true,
        version: 3,
      );
      expect(settings.copyWith().muteConfig, isNotNull);
      expect(settings.copyWith(muteConfig: null).muteConfig, isNull);
      expect(settings.copyWith(muted: false).muteConfig, isNotNull);
      expect(settings.copyWith(version: 4).version, 4);
      expect(
        settings.copyWith(hideMutedChannels: false).hideMutedChannels,
        isFalse,
      );
      expect(settings.copyWith(mobilePush: false).mobilePush, isFalse);
      expect(
        settings
            .copyWith(notifyHighlights: NotifyHighlights.disabled)
            .notifyHighlights,
        NotifyHighlights.disabled,
      );
      expect(settings.copyWith(suppressRoles: false).suppressRoles, isFalse);
      expect(
        settings.copyWith(muteScheduledEvents: false).muteScheduledEvents,
        isFalse,
      );
      expect(settings.copyWith(flags: 7).flags, 7);
      expect(settings.unreadBadge, isNull);
    });

    test('reads an override mute expiry and its badge flags', () {
      const override = ChannelNotificationOverride(
        channelId: _channelId,
        muted: true,
        muteConfig: NotificationMuteConfig(selectedTimeWindowSeconds: -1),
        collapsed: true,
      );
      expect(override.isMutedAt(DateTime.utc(2030)), isTrue);
      expect(override.collapsed, isTrue);
      expect(override.unreadBadge, isNull);
      expect(
        const ChannelNotificationOverride(
          channelId: _channelId,
          flags: ChannelOverrideFlags.favorited,
        ).unreadBadge,
        isNull,
      );
    });
  });

  group('enums', () {
    test('map wire values and fall back where told to', () {
      expect(
        MessageNotificationLevel.fromWire(
          2,
          orElse: MessageNotificationLevel.inherit,
        ),
        MessageNotificationLevel.noMessages,
      );
      expect(
        MessageNotificationLevel.fromWire(
          9,
          orElse: MessageNotificationLevel.inherit,
        ),
        MessageNotificationLevel.inherit,
      );
      expect(
        MessageNotificationLevel.fromWire(
          null,
          orElse: MessageNotificationLevel.allMessages,
        ),
        MessageNotificationLevel.allMessages,
      );
      expect(NotifyHighlights.fromWire(2), NotifyHighlights.enabled);
      expect(NotifyHighlights.fromWire(7), NotifyHighlights.unset);
      expect(NotifyHighlights.fromWire('2'), NotifyHighlights.unset);
    });

    test('patches report emptiness', () {
      expect(const GuildNotificationSettingsPatch().isEmpty, isTrue);
      expect(
        const GuildNotificationSettingsPatch(clearMuteConfig: true).isEmpty,
        isFalse,
      );
      expect(
        const GuildNotificationSettingsPatch(mobilePush: false).isEmpty,
        isFalse,
      );
      expect(const ChannelNotificationOverridePatch().isEmpty, isTrue);
      expect(
        const ChannelNotificationOverridePatch(collapsed: true).isEmpty,
        isFalse,
      );
    });
  });

  _projectionCases();
}

ConversationChannel _channel({
  required String id,
  String spaceId = _guildId,
  String? parentId,
  bool isThread = false,
}) => ConversationChannel(
  id: id,
  spaceId: spaceId,
  name: 'general',
  topic: '',
  kind: ChannelKind.text,
  parentId: parentId,
  isThread: isThread,
);

ReadStateSnapshot _snapshotWith(
  GuildNotificationSettings settings, {
  int accountFlags = 0,
}) => ReadStateSnapshot(
  settings: {settings.spaceId: settings},
  accountNotificationFlags: accountFlags,
);

ChatWorkspace _workspace() => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: _guildId,
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: _channelId,
      spaceId: _guildId,
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      lastMessageId: _newestMessage,
    ),
  ],
  members: const [
    Member(
      id: _categoryId,
      displayName: 'Flucord',
      initials: 'FL',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  messages: [
    ChatMessage(
      id: _olderMessage,
      channelId: _channelId,
      authorId: _categoryId,
      body: 'read',
      sentAt: DateTime.utc(2026, 7, 20),
    ),
    ChatMessage(
      id: _newerMessage,
      channelId: _channelId,
      authorId: _categoryId,
      body: 'first unread',
      sentAt: DateTime.utc(2026, 7, 21),
    ),
    ChatMessage(
      id: _newestMessage,
      channelId: _channelId,
      authorId: _categoryId,
      body: 'newest',
      sentAt: DateTime.utc(2026, 7, 22),
    ),
  ],
  currentMemberId: _categoryId,
);
