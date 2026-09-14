import 'package:flucord/src/data/discord/discord_read_state_codec.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _guildId = '111111111111111111';
const _channelId = '222222222222222222';
const _categoryId = '333333333333333333';
const _messageId = '234567890123456789';

void main() {
  group('read-state entries', () {
    test('reads the channel dialect', () {
      final state = DiscordReadStateCodec.readState({
        'id': _channelId,
        'mention_count': 3,
        'last_message_id': _messageId,
        'last_pin_timestamp': '2026-07-20T10:00:00+00:00',
        'flags': 1,
        'last_viewed': 2400,
      });

      expect(state!.entityId, _channelId);
      expect(state.type, ReadStateType.channel);
      expect(state.mentionCount, 3);
      expect(state.lastAckedId, _messageId);
      expect(state.flags, 1);
      expect(state.lastViewed, 2400);
      expect(state.lastPinTimestamp, DateTime.utc(2026, 7, 20, 10));
    });

    test('reads the non-channel dialect off the other field names', () {
      final state = DiscordReadStateCodec.readState({
        'id': _guildId,
        'read_state_type': 1,
        'badge_count': 2,
        'last_acked_id': _messageId,
        // The channel-dialect names are present and must be ignored, which is
        // the mistake that makes a guild event permanently unread.
        'mention_count': 99,
        'last_message_id': _channelId,
      });

      expect(state!.type, ReadStateType.guildEvent);
      expect(state.entityId, _guildId);
      expect(state.mentionCount, 2);
      expect(state.lastAckedId, _messageId);
      expect(state.key, '1:$_guildId');
    });

    test('drops an entry with no id or an unmodelled type', () {
      expect(DiscordReadStateCodec.readState(const {}), isNull);
      expect(DiscordReadStateCodec.readState(const {'id': ''}), isNull);
      expect(DiscordReadStateCodec.readState(const {'id': 7}), isNull);
      expect(
        DiscordReadStateCodec.readState(const {
          'id': _guildId,
          'read_state_type': 6,
        }),
        isNull,
      );
    });

    test('normalises numeric, zero and missing cursors', () {
      expect(
        DiscordReadStateCodec.readState(const {
          'id': _channelId,
          'last_message_id': 0,
        })!.lastAckedId,
        isNull,
      );
      expect(
        DiscordReadStateCodec.readState(const {
          'id': _channelId,
          'last_message_id': '',
        })!.lastAckedId,
        isNull,
      );
      expect(
        DiscordReadStateCodec.readState(const {
          'id': _channelId,
          'last_message_id': 12,
        })!.lastAckedId,
        '12',
      );
      final bare = DiscordReadStateCodec.readState(const {'id': _channelId})!;
      expect(bare.lastAckedId, isNull);
      expect(bare.mentionCount, 0);
      expect(bare.flags, 0);
      expect(bare.lastViewed, isNull);
      expect(bare.lastPinTimestamp, isNull);
    });

    test('accepts floating point counts and refuses negative ones', () {
      final state = DiscordReadStateCodec.readState(const {
        'id': _channelId,
        'mention_count': -4,
        'flags': 2.0,
        'last_viewed': 12.0,
        'last_pin_timestamp': 42,
      })!;
      expect(state.mentionCount, 0);
      expect(state.flags, 2);
      expect(state.lastViewed, 12);
      expect(state.lastPinTimestamp, isNull);
    });
  });

  group('guild settings', () {
    test('reads a full entry and keys DMs under the pseudo-guild', () {
      final settings = DiscordReadStateCodec.guildSettings({
        'guild_id': _guildId,
        'muted': true,
        'mute_config': {
          'selected_time_window': 3600,
          'end_time': '2026-07-26T13:00:00+00:00',
        },
        'message_notifications': 1,
        'suppress_everyone': true,
        'suppress_roles': true,
        'mute_scheduled_events': true,
        'mobile_push': false,
        'notify_highlights': 2,
        'hide_muted_channels': true,
        'flags': 4096,
        'version': 12,
        'channel_overrides': [
          {
            'channel_id': _channelId,
            'muted': true,
            'message_notifications': 2,
            'flags': 512,
            'collapsed': true,
            'mute_config': {'selected_time_window': -1, 'end_time': null},
          },
        ],
      });

      expect(settings.spaceId, _guildId);
      expect(settings.muted, isTrue);
      expect(settings.muteConfig!.selectedTimeWindowSeconds, 3600);
      expect(settings.muteConfig!.endTime, DateTime.utc(2026, 7, 26, 13));
      expect(
        settings.messageNotifications,
        MessageNotificationLevel.onlyMentions,
      );
      expect(settings.suppressEveryone, isTrue);
      expect(settings.suppressRoles, isTrue);
      expect(settings.muteScheduledEvents, isTrue);
      expect(settings.mobilePush, isFalse);
      expect(settings.notifyHighlights, NotifyHighlights.enabled);
      expect(settings.hideMutedChannels, isTrue);
      expect(settings.flags, GuildNotificationFlags.unreadsOnlyMentions);
      expect(settings.version, 12);

      final override = settings.overrideFor(_channelId)!;
      expect(override.muted, isTrue);
      expect(
        override.messageNotifications,
        MessageNotificationLevel.noMessages,
      );
      expect(override.flags, ChannelOverrideFlags.unreadsOnlyMentions);
      expect(override.collapsed, isTrue);
      expect(override.muteConfig!.isPermanent, isTrue);
    });

    test('falls back to the store defaults for an empty entry', () {
      final settings = DiscordReadStateCodec.guildSettings(const {});
      expect(settings.spaceId, CommunitySpace.directMessagesId);
      expect(settings.muted, isFalse);
      expect(settings.muteConfig, isNull);
      expect(
        settings.messageNotifications,
        MessageNotificationLevel.allMessages,
      );
      expect(settings.mobilePush, isTrue);
      expect(settings.notifyHighlights, NotifyHighlights.unset);
      expect(settings.version, -1);
      expect(settings.channelOverrides, isEmpty);
      expect(
        DiscordReadStateCodec.guildSettings(const {'guild_id': ''}).spaceId,
        CommunitySpace.directMessagesId,
      );
    });

    test('accepts channel overrides as an array or a map', () {
      final fromMap = DiscordReadStateCodec.channelOverrides({
        _channelId: const {'muted': true},
        '': const {'muted': true},
        _categoryId: 'not an object',
      });
      expect(fromMap.keys, [_channelId]);

      final fromList = DiscordReadStateCodec.channelOverrides([
        {'channel_id': _channelId, 'muted': true},
        {'muted': true},
        {'channel_id': 5},
        'junk',
      ]);
      expect(fromList.keys, [_channelId]);
      expect(DiscordReadStateCodec.channelOverrides(null), isEmpty);

      // An override with no explicit level inherits rather than defaulting to
      // "all messages", which is the difference between a channel following its
      // guild and one shouting over it.
      expect(
        fromList[_channelId]!.messageNotifications,
        MessageNotificationLevel.inherit,
      );
    });

    test('reads a mute config only from an object', () {
      expect(DiscordReadStateCodec.muteConfig(null), isNull);
      expect(DiscordReadStateCodec.muteConfig('always'), isNull);
      final bare = DiscordReadStateCodec.muteConfig(const <String, Object?>{})!;
      expect(
        bare.selectedTimeWindowSeconds,
        NotificationMuteConfig.alwaysWindow,
      );
      expect(bare.endTime, isNull);
      expect(
        DiscordReadStateCodec.muteConfig(const {
          'end_time': 'not a date',
        })!.endTime,
        isNull,
      );
    });
  });

  group('patch bodies', () {
    test('sends only the leaves that changed', () {
      expect(
        DiscordReadStateCodec.guildSettingsBody(
          const GuildNotificationSettingsPatch(),
        ),
        isEmpty,
      );

      final body = DiscordReadStateCodec.guildSettingsBody(
        GuildNotificationSettingsPatch(
          muted: true,
          muteConfig: NotificationMuteConfig(
            selectedTimeWindowSeconds: 900,
            endTime: DateTime.utc(2026, 7, 26, 12, 15),
          ),
          messageNotifications: MessageNotificationLevel.onlyMentions,
          suppressEveryone: true,
          suppressRoles: false,
          muteScheduledEvents: true,
          mobilePush: false,
          notifyHighlights: NotifyHighlights.disabled,
          flags: 2048,
        ),
      );
      expect(body, {
        'muted': true,
        'mute_config': {
          'selected_time_window': 900,
          'end_time': '2026-07-26T12:15:00.000Z',
        },
        'message_notifications': 1,
        'suppress_everyone': true,
        'suppress_roles': false,
        'mute_scheduled_events': true,
        'mobile_push': false,
        'notify_highlights': 1,
        'flags': 2048,
      });
    });

    test('clearing the mute config beats setting it', () {
      expect(
        DiscordReadStateCodec.guildSettingsBody(
          GuildNotificationSettingsPatch(
            clearMuteConfig: true,
            muteConfig: const NotificationMuteConfig(
              selectedTimeWindowSeconds: 900,
            ),
          ),
        ),
        {'mute_config': null},
      );
      expect(
        DiscordReadStateCodec.channelOverrideBody(
          const ChannelNotificationOverridePatch(clearMuteConfig: true),
        ),
        {'mute_config': null},
      );
    });

    test('builds a channel override body', () {
      expect(
        DiscordReadStateCodec.channelOverrideBody(
          const ChannelNotificationOverridePatch(),
        ),
        isEmpty,
      );
      expect(
        DiscordReadStateCodec.channelOverrideBody(
          ChannelNotificationOverridePatch(
            muted: true,
            muteConfig: NotificationMuteConfig.forWindow(
              -1,
              now: DateTime.utc(2026),
            ),
            messageNotifications: MessageNotificationLevel.noMessages,
            flags: 1024,
            collapsed: false,
          ),
        ),
        {
          'muted': true,
          'mute_config': {'selected_time_window': -1, 'end_time': null},
          'message_notifications': 2,
          'flags': 1024,
          'collapsed': false,
        },
      );
    });
  });

  group('optimistic apply', () {
    test('mirrors the guild patch the server will apply', () {
      final settings = GuildNotificationSettings(
        spaceId: _guildId,
        muteConfig: const NotificationMuteConfig(
          selectedTimeWindowSeconds: 900,
        ),
        mobilePush: false,
      );

      final muted = DiscordReadStateCodec.applyGuildPatch(
        settings,
        const GuildNotificationSettingsPatch(muted: true),
      );
      expect(muted.muted, isTrue);
      expect(muted.muteConfig, isNotNull);
      expect(muted.mobilePush, isFalse);

      final cleared = DiscordReadStateCodec.applyGuildPatch(
        settings,
        const GuildNotificationSettingsPatch(
          muted: false,
          clearMuteConfig: true,
        ),
      );
      expect(cleared.muteConfig, isNull);

      final replaced = DiscordReadStateCodec.applyGuildPatch(
        settings,
        GuildNotificationSettingsPatch(
          muteConfig: NotificationMuteConfig.forWindow(
            3600,
            now: DateTime.utc(2026, 7, 26, 12),
          ),
          notifyHighlights: NotifyHighlights.enabled,
        ),
      );
      expect(replaced.muteConfig!.selectedTimeWindowSeconds, 3600);
      expect(replaced.notifyHighlights, NotifyHighlights.enabled);
    });

    test('mirrors the override patch', () {
      const override = ChannelNotificationOverride(
        channelId: _channelId,
        flags: ChannelOverrideFlags.favorited,
        collapsed: true,
      );

      final applied = DiscordReadStateCodec.applyOverridePatch(
        override,
        const ChannelNotificationOverridePatch(
          muted: true,
          messageNotifications: MessageNotificationLevel.onlyMentions,
        ),
      );
      expect(applied.muted, isTrue);
      expect(applied.flags, ChannelOverrideFlags.favorited);
      expect(applied.collapsed, isTrue);
      expect(
        applied.messageNotifications,
        MessageNotificationLevel.onlyMentions,
      );

      final cleared = DiscordReadStateCodec.applyOverridePatch(
        ChannelNotificationOverride(
          channelId: _channelId,
          muteConfig: NotificationMuteConfig.forWindow(
            900,
            now: DateTime.utc(2026),
          ),
        ),
        const ChannelNotificationOverridePatch(clearMuteConfig: true),
      );
      expect(cleared.muteConfig, isNull);
    });
  });
}
