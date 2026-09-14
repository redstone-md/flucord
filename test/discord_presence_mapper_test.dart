import 'package:flucord/src/data/discord/discord_presence_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('presence records', () {
    test('reads every documented field of a presence object', () {
      final record = DiscordPresenceMapper.record({
        'user': {'id': '222222222222222222', 'username': 'mira'},
        'status': 'dnd',
        'client_status': {'desktop': 'dnd', 'mobile': 'online', 'holo': 'idle'},
        'guild_id': '111111111111111111',
        'processed_at_timestamp': 1770000000000,
        'activities': [
          {'name': 'Elden Ring', 'type': 0},
        ],
        'hidden_activities': [
          {'name': 'Secret', 'type': 0},
        ],
      });

      expect(record, isNotNull);
      expect(record!.userId, '222222222222222222');
      expect(record.guildId, '111111111111111111');
      expect(record.processedAtTimestamp, 1770000000000);
      expect(record.user?['username'], 'mira');
      expect(record.presence.status, Presence.doNotDisturb);
      expect(
        record.presence.clientStatus[ClientPlatform.desktop],
        Presence.doNotDisturb,
      );
      expect(
        record.presence.clientStatus[ClientPlatform.mobile],
        Presence.online,
      );
      // An unrecognised device key folds into `unknown` rather than vanishing.
      expect(
        record.presence.clientStatus[ClientPlatform.unknown],
        Presence.idle,
      );
      expect(record.presence.activities.single.name, 'Elden Ring');
      expect(record.presence.hiddenActivities.single.name, 'Secret');
    });

    test('accepts the compressed READY form and the scope it was found in', () {
      final record = DiscordPresenceMapper.record({
        'user_id': '333333333333333333',
        'status': 'online',
      }, guildId: '111111111111111111');

      expect(record!.userId, '333333333333333333');
      expect(record.guildId, '111111111111111111');
      expect(record.user, isNull);
      expect(record.presence.clientStatus, isEmpty);
      expect(record.processedAtTimestamp, 0);
    });

    test('refuses a presence that names no user', () {
      expect(DiscordPresenceMapper.record(const {'status': 'online'}), isNull);
      expect(
        DiscordPresenceMapper.record(const {'user': <String, Object?>{}}),
        isNull,
      );
      expect(DiscordPresenceMapper.record(const {'user_id': ''}), isNull);
    });

    test('maps an array and drops the unusable entries', () {
      final records = DiscordPresenceMapper.records([
        {
          'user': {'id': '222222222222222222'},
          'status': 'idle',
        },
        {'status': 'online'},
        'not an object',
      ], guildId: '111111111111111111');

      expect(records, hasLength(1));
      expect(records.single.presence.status, Presence.idle);
      expect(DiscordPresenceMapper.records('not a list'), isEmpty);
    });

    test('reads client_status defensively', () {
      expect(DiscordPresenceMapper.clientStatus(null), isEmpty);
      expect(DiscordPresenceMapper.clientStatus(const {7: 'online'}), isEmpty);
    });
  });

  group('activities', () {
    test('reads the full read-schema activity', () {
      final activity = DiscordPresenceMapper.activity({
        'session_id': 'abc',
        'type': 2,
        'name': 'Spotify',
        'url': 'https://example.invalid/live',
        'application_id': '987654321098765432',
        'status_display_type': 1,
        'state': 'Some Artist',
        'state_url': 'https://example.invalid/state',
        'details': 'Some Track',
        'details_url': 'https://example.invalid/details',
        'emoji': {
          'name': 'party',
          'id': '123456789012345678',
          'animated': true,
        },
        'assets': {
          'large_image': 'spotify:cover',
          'large_text': 'Album',
          'large_url': 'https://example.invalid/large',
          'small_image': 'mp:external/thumb.png',
          'small_text': 'Playing',
          'small_url': 'https://example.invalid/small',
        },
        'timestamps': {'start': 1000, 'end': 5000},
        'party': {
          'id': 'party-1',
          'size': [2, 5],
          'privacy': 1,
        },
        'secrets': {'match': 'm', 'join': 'j'},
        'sync_id': 'track-1',
        'created_at': 900,
        'instance': true,
        'flags': 48,
        'platform': 'desktop',
        'supported_platforms': ['desktop', 'ios'],
        'buttons': ['Listen along'],
      });

      expect(activity, isNotNull);
      expect(activity!.type, ActivityType.listening);
      expect(activity.sessionId, 'abc');
      expect(activity.statusDisplayType, StatusDisplayType.state);
      expect(activity.stateUrl, 'https://example.invalid/state');
      expect(activity.detailsUrl, 'https://example.invalid/details');
      expect(activity.emoji!.isCustom, isTrue);
      expect(activity.emoji!.animated, isTrue);
      expect(activity.emoji!.imageUrl, contains('/emojis/123456789012345678'));
      expect(activity.assets!.largeImageUrl, 'https://i.scdn.co/image/cover');
      expect(
        activity.assets!.smallImageUrl,
        'https://media.discordapp.net/external/thumb.png',
      );
      expect(activity.assets!.largeUrl, 'https://example.invalid/large');
      expect(activity.assets!.smallUrl, 'https://example.invalid/small');
      expect(activity.timestamps!.startMs, 1000);
      expect(activity.timestamps!.endMs, 5000);
      // Listening never counts down, even with an end past created_at.
      expect(activity.timestamps!.isCountDown, isFalse);
      expect(activity.party!.currentSize, 2);
      expect(activity.party!.maxSize, 5);
      expect(activity.party!.privacy, ActivityPartyPrivacy.public);
      expect(activity.secrets!.match, 'm');
      expect(activity.secrets!.join, 'j');
      expect(activity.syncId, 'track-1');
      expect(activity.createdAtMs, 900);
      expect(activity.instance, isTrue);
      expect(activity.hasFlag(ActivityFlag.sync), isTrue);
      expect(activity.hasFlag(ActivityFlag.play), isTrue);
      expect(activity.hasFlag(ActivityFlag.join), isFalse);
      expect(activity.platform, 'desktop');
      expect(activity.supportedPlatforms, ['desktop', 'ios']);
      expect(activity.buttons, ['Listen along']);
    });

    test('marks a countdown for a non-listening activity', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Match',
        'type': 5,
        'created_at': 100,
        'timestamps': {'end': 900},
      });

      expect(activity!.timestamps!.isCountDown, isTrue);
      expect(activity.timestamps!.startMs, isNull);
    });

    test('refuses an activity without a name', () {
      expect(DiscordPresenceMapper.activity(const {'type': 0}), isNull);
      expect(DiscordPresenceMapper.activity(const {'name': ''}), isNull);
    });

    test('an unrecognised type keeps the activity renderable', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Something new',
        'type': 99,
      });

      expect(activity!.type, ActivityType.unrecognised);
      expect(activity.summary, 'Something new');
    });

    test('leaves absent submessages null rather than empty', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Bare',
        'emoji': <String, Object?>{},
        'assets': <String, Object?>{},
        'timestamps': <String, Object?>{},
        'party': <String, Object?>{},
        'secrets': <String, Object?>{},
      });

      expect(activity!.emoji, isNull);
      expect(activity.assets, isNull);
      expect(activity.timestamps, isNull);
      expect(activity.party, isNull);
      expect(activity.secrets, isNull);
      expect(activity.statusDisplayType, StatusDisplayType.name);
    });

    test('ignores submessages that are not objects', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Bare',
        'emoji': 'nope',
        'assets': 'nope',
        'timestamps': 'nope',
        'party': 'nope',
        'secrets': 'nope',
        'supported_platforms': 'nope',
        'buttons': 'nope',
      });

      expect(activity!.emoji, isNull);
      expect(activity.assets, isNull);
      expect(activity.timestamps, isNull);
      expect(activity.party, isNull);
      expect(activity.secrets, isNull);
      expect(activity.supportedPlatforms, isEmpty);
      expect(activity.buttons, isEmpty);
    });

    test('a party of any other length reports no size', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Raid',
        'party': {
          'size': [3],
        },
      });

      expect(activity!.party, isNull);
    });

    test('keeps a party that only carries a privacy flag', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Raid',
        'party': {'privacy': 0},
      });

      expect(activity!.party!.privacy, ActivityPartyPrivacy.private);
      expect(activity.party!.hasSize, isFalse);
    });

    test('a unicode emoji carries no image', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Custom Status',
        'type': 4,
        'emoji': {'name': '🛠'},
      });

      expect(activity!.emoji!.isCustom, isFalse);
      expect(activity.emoji!.imageUrl, isNull);
    });

    test('a negative flags value grants no bits', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Hostile',
        'flags': -1,
      });

      expect(activity!.flags, 0);
      expect(activity.hasFlag(ActivityFlag.join), isFalse);
      expect(activity.hasFlag(ActivityFlag.supportsJoinUrl), isFalse);
    });

    test('bounds the wire-supplied list lengths', () {
      final record = DiscordPresenceMapper.record({
        'user': {'id': '222222222222222222'},
        'status': 'online',
        'activities': [
          for (var index = 0; index < 200; index++) {'name': 'Game $index'},
        ],
      });

      expect(
        record!.presence.activities,
        hasLength(DiscordPresenceMapper.maxActivities),
      );

      final activity = DiscordPresenceMapper.activity({
        'name': 'Bounded',
        'buttons': ['a', 'b', 'c', 'd'],
        'supported_platforms': [
          for (var index = 0; index < 40; index++) 'p$index',
        ],
      });
      expect(activity!.buttons, hasLength(DiscordPresenceMapper.maxButtons));
      expect(
        activity.supportedPlatforms,
        hasLength(DiscordPresenceMapper.maxSupportedPlatforms),
      );
    });

    test('truncates a text leaf instead of handing it to a painter', () {
      final activity = DiscordPresenceMapper.activity({
        'name': 'x' * 5000,
        'buttons': ['y' * 5000, ''],
      });

      expect(activity!.name, hasLength(DiscordPresenceMapper.maxTextLength));
      expect(
        activity.buttons.single,
        hasLength(DiscordPresenceMapper.maxTextLength),
      );
    });

    test('reads numbers written as doubles and decimal strings', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Numeric',
        'created_at': 1.0,
        'timestamps': {'start': '2000', 'end': 3000.4},
      });

      expect(activity!.createdAtMs, 1);
      expect(activity.timestamps!.startMs, 2000);
      expect(activity.timestamps!.endMs, 3000);
    });

    test('refuses numbers that are neither finite nor numeric', () {
      final activity = DiscordPresenceMapper.activity(const {
        'name': 'Numeric',
        'created_at': double.nan,
        'timestamps': {'start': 'soon', 'end': true},
      });

      expect(activity!.createdAtMs, isNull);
      expect(activity.timestamps, isNull);
    });
  });

  group('sessions', () {
    test('reads a session and its operating system', () {
      final session = DiscordPresenceMapper.session(const {
        'session_id': 'session-1',
        'last_modified': 1770000000000,
        'status': 'idle',
        'active': true,
        'client_info': {'os': 'windows'},
        'activities': [
          {'name': 'Elden Ring'},
        ],
        'hidden_activities': [
          {'name': 'Hidden'},
        ],
      });

      expect(session!.sessionId, 'session-1');
      expect(session.lastModified, 1770000000000);
      expect(session.status, Presence.idle);
      expect(session.active, isTrue);
      expect(session.operatingSystem, 'windows');
      expect(session.activities.single.name, 'Elden Ring');
      expect(session.hiddenActivities.single.name, 'Hidden');
    });

    test('defaults a session with nothing but an id', () {
      final session = DiscordPresenceMapper.session(const {
        'session_id': 'session-2',
      });

      expect(session!.status, Presence.unknown);
      expect(session.lastModified, 0);
      expect(session.active, isFalse);
      expect(session.operatingSystem, isNull);
      expect(session.activities, isEmpty);
    });

    test('refuses a session without an id', () {
      expect(DiscordPresenceMapper.session(const {}), isNull);
      expect(DiscordPresenceMapper.session(const {'session_id': ''}), isNull);
    });

    test('maps the bare array SESSIONS_REPLACE dispatches', () {
      final sessions = DiscordPresenceMapper.sessions([
        {'session_id': 'a'},
        {'no': 'id'},
        42,
      ]);

      expect(sessions, hasLength(1));
      expect(DiscordPresenceMapper.sessions(null), isEmpty);
    });
  });
}
