import 'package:flucord/src/data/discord/discord_self_presence.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 7, 26, 12);

void main() {
  group('composition', () {
    test('defaults to online with nothing stored', () {
      final presence = DiscordSelfPresence.compose(now: _now);

      expect(presence.status, Presence.online);
      expect(presence.since, 0);
      expect(presence.afk, isFalse);
      expect(presence.activities, isEmpty);
    });

    test('an unset or unknown stored status still reads as online', () {
      expect(
        DiscordSelfPresence.compose(
          now: _now,
          stored: const StatusPreferences(status: ''),
        ).status,
        Presence.online,
      );
      expect(
        DiscordSelfPresence.compose(
          now: _now,
          stored: const StatusPreferences(status: 'unknown'),
        ).status,
        Presence.online,
      );
    });

    test('promotes online to idle, and only online', () {
      final online = DiscordSelfPresence.compose(
        now: _now,
        stored: const StatusPreferences(status: 'online'),
        idleSince: 1770000000000,
      );
      expect(online.status, Presence.idle);
      expect(online.since, 1770000000000);

      final busy = DiscordSelfPresence.compose(
        now: _now,
        stored: const StatusPreferences(status: 'dnd'),
        idleSince: 1770000000000,
      );
      expect(busy.status, Presence.doNotDisturb);
      expect(busy.since, 1770000000000);
    });

    test('carries the away flag through untouched', () {
      expect(DiscordSelfPresence.compose(now: _now, afk: true).afk, isTrue);
    });

    test('an invisible session broadcasts no activities at all', () {
      final presence = DiscordSelfPresence.compose(
        now: _now,
        stored: const StatusPreferences(
          status: 'invisible',
          customStatusText: 'Heads down',
        ),
        localActivities: const [UserActivity(name: 'Elden Ring')],
      );

      expect(presence.status, Presence.invisible);
      expect(presence.activities, isEmpty);
    });

    test('a forced invisible session overrides the stored status', () {
      final presence = DiscordSelfPresence.compose(
        now: _now,
        stored: const StatusPreferences(status: 'online'),
        forcedInvisible: true,
      );

      expect(presence.status, Presence.invisible);
    });

    test('puts the custom status ahead of the local activities', () {
      final presence = DiscordSelfPresence.compose(
        now: _now,
        stored: const StatusPreferences(customStatusText: 'Heads down'),
        localActivities: const [UserActivity(name: 'Elden Ring')],
      );

      expect(presence.activities.first.type, ActivityType.customStatus);
      expect(presence.activities.last.name, 'Elden Ring');
    });

    test('drops an activity the account is not sharing', () {
      final presence = DiscordSelfPresence.compose(
        now: _now,
        localActivities: const [
          UserActivity(name: 'Private', applicationId: '987654321098765432'),
          UserActivity(
            name: 'Contextless',
            applicationId: '987654321098765432',
            flags: ActivityFlag.contextless,
          ),
        ],
      );

      expect(presence.activities.map((activity) => activity.name), [
        'Contextless',
      ]);
    });
  });

  group('custom status', () {
    test('is absent when the account carries none', () {
      expect(
        DiscordSelfPresence.customStatus(const StatusPreferences(), now: _now),
        isNull,
      );
    });

    test('carries the text, the emoji and the expiry', () {
      final activity = DiscordSelfPresence.customStatus(
        StatusPreferences(
          customStatusText: 'Heads down',
          customStatusEmojiName: '🛠',
          customStatusExpiresAtMs: _now.millisecondsSinceEpoch + 60000,
        ),
        now: _now,
      );

      expect(activity!.name, DiscordSelfPresence.customStatusName);
      expect(activity.type, ActivityType.customStatus);
      expect(activity.state, 'Heads down');
      expect(activity.emoji!.name, '🛠');
      expect(activity.emoji!.isCustom, isFalse);
      expect(activity.timestamps!.endMs, _now.millisecondsSinceEpoch + 60000);
    });

    test('an emoji alone is a valid custom status', () {
      final activity = DiscordSelfPresence.customStatus(
        const StatusPreferences(
          customStatusEmojiName: 'shipit',
          customStatusEmojiId: '123456789012345678',
        ),
        now: _now,
      );

      expect(activity!.state, isNull);
      expect(activity.emoji!.isCustom, isTrue);
      expect(activity.timestamps, isNull);
    });

    test('an expired status is simply not built', () {
      expect(
        DiscordSelfPresence.customStatus(
          StatusPreferences(
            customStatusText: 'Back soon',
            customStatusExpiresAtMs: _now.millisecondsSinceEpoch,
          ),
          now: _now,
        ),
        isNull,
      );
    });
  });

  group('wire form', () {
    test('sends exactly the four documented keys', () {
      final payload = DiscordSelfPresence.toWire(
        const SelfPresence(status: Presence.idle, since: 42, afk: true),
      );

      expect(payload.keys, ['status', 'since', 'activities', 'afk']);
      expect(payload['status'], 'idle');
      expect(payload['since'], 42);
      expect(payload['afk'], isTrue);
      expect(payload['activities'], isEmpty);
    });

    test('writes only the activity keys this client produces', () {
      final payload = DiscordSelfPresence.activityToWire(
        const UserActivity(
          name: 'Custom Status',
          type: ActivityType.customStatus,
          state: 'Heads down',
          emoji: ActivityEmoji(name: '🛠'),
          timestamps: ActivityTimestamps(endMs: 1770000000000),
        ),
      );

      expect(payload, {
        'name': 'Custom Status',
        'type': 4,
        'state': 'Heads down',
        'emoji': {'name': '🛠', 'id': null, 'animated': false},
        'timestamps': {'end': 1770000000000},
      });
    });

    test('writes a custom emoji by id and every optional string it has', () {
      final payload = DiscordSelfPresence.activityToWire(
        const UserActivity(
          name: 'Elden Ring',
          details: 'Limgrave',
          url: 'https://example.invalid/live',
          applicationId: '987654321098765432',
          emoji: ActivityEmoji(
            name: 'shipit',
            id: '123456789012345678',
            animated: true,
          ),
          timestamps: ActivityTimestamps(startMs: 1, endMs: 2),
        ),
      );

      expect(payload['details'], 'Limgrave');
      expect(payload['url'], 'https://example.invalid/live');
      expect(payload['application_id'], '987654321098765432');
      expect(payload['emoji'], {
        'name': 'shipit',
        'id': '123456789012345678',
        'animated': true,
      });
      expect(payload['timestamps'], {'start': 1, 'end': 2});
    });

    test('omits an empty timestamps object', () {
      final payload = DiscordSelfPresence.activityToWire(
        const UserActivity(name: 'Bare', timestamps: ActivityTimestamps()),
      );

      expect(payload.containsKey('timestamps'), isFalse);
    });
  });
}
