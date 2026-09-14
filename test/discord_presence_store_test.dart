import 'package:flucord/src/data/discord/discord_presence_mapper.dart';
import 'package:flucord/src/data/discord/discord_presence_store.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _mira = '222222222222222222';
const _roman = '333333333333333333';
const _forge = '111111111111111111';
const _atlas = '123456789012345678';

DiscordPresenceRecord _record({
  String userId = _mira,
  String? guildId,
  Presence status = Presence.online,
  int processedAt = 0,
  List<UserActivity> activities = const [],
  List<UserActivity> hidden = const [],
  Map<ClientPlatform, Presence> clientStatus = const {},
}) => DiscordPresenceRecord(
  userId: userId,
  guildId: guildId,
  processedAtTimestamp: processedAt,
  presence: UserPresence(
    status: status,
    clientStatus: clientStatus,
    activities: activities,
    hiddenActivities: hidden,
  ),
);

UserActivity _activity(
  String name, {
  ActivityType type = ActivityType.playing,
  int? createdAt,
  String? applicationId,
  String? partyId,
  String? details,
}) => UserActivity(
  name: name,
  type: type,
  createdAtMs: createdAt,
  applicationId: applicationId,
  details: details,
  party: partyId == null ? null : ActivityParty(id: partyId),
);

void main() {
  group('store', () {
    test('publishes a presence and reports it as changed', () {
      final store = DiscordPresenceStore();

      final changed = store.apply([
        _record(guildId: _forge, activities: [_activity('Elden Ring')]),
      ]);

      expect(changed.keys, [_mira]);
      expect(changed[_mira]!.status, Presence.online);
      expect(store.presenceFor(_mira)!.activities.single.name, 'Elden Ring');
      expect(store.all.keys, [_mira]);
    });

    test('never stores the account it is signed in as', () {
      final store = DiscordPresenceStore()
        ..apply([_record(guildId: _forge)])
        ..currentUserId = _mira;

      expect(store.presenceFor(_mira), isNull);
      expect(store.apply([_record(guildId: _forge)]), isEmpty);
    });

    test('drops an offline presence for a user it has never seen', () {
      final store = DiscordPresenceStore();

      expect(
        store.apply([_record(status: Presence.offline, guildId: _forge)]),
        isEmpty,
      );
      expect(store.presenceFor(_mira), isNull);
    });

    test('keeps an offline presence that still hides an activity', () {
      final store = DiscordPresenceStore();

      final changed = store.apply([
        _record(
          status: Presence.offline,
          guildId: _forge,
          hidden: [_activity('Private game')],
        ),
      ]);

      expect(changed[_mira]!.status, Presence.offline);
      expect(changed[_mira]!.hiddenActivities.single.name, 'Private game');
    });

    test('going offline empties the activities and then drops the user', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(guildId: _forge, activities: [_activity('Elden Ring')]),
        ]);

      final changed = store.apply([
        _record(status: Presence.offline, guildId: _forge, processedAt: 2),
      ]);

      expect(changed[_mira]!.status, Presence.offline);
      expect(changed[_mira]!.activities, isEmpty);
      expect(store.presenceFor(_mira), isNull);
      expect(store.all, isEmpty);
    });

    test('collapses across guilds by processed_at_timestamp', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(guildId: _forge, status: Presence.online, processedAt: 100),
          _record(guildId: _atlas, status: Presence.idle, processedAt: 200),
        ]);

      expect(store.presenceFor(_mira)!.status, Presence.idle);

      store.apply([
        _record(
          guildId: _forge,
          status: Presence.doNotDisturb,
          processedAt: 300,
        ),
      ]);

      expect(store.presenceFor(_mira)!.status, Presence.doNotDisturb);
    });

    test('a stale frame from another guild does not win', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(
            guildId: _forge,
            status: Presence.doNotDisturb,
            processedAt: 900,
          ),
        ])
        ..apply([
          _record(guildId: _atlas, status: Presence.online, processedAt: 100),
        ]);

      expect(store.presenceFor(_mira)!.status, Presence.doNotDisturb);
    });

    test('a tie breaks toward the entry carrying more activities', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(guildId: _forge, processedAt: 500),
          _record(
            guildId: _atlas,
            processedAt: 500,
            status: Presence.idle,
            activities: [_activity('Elden Ring')],
          ),
        ]);

      final presence = store.presenceFor(_mira)!;
      expect(presence.status, Presence.idle);
      expect(presence.activities.single.name, 'Elden Ring');
    });

    test('unions and dedupes hidden activities across every scope', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(
            guildId: _forge,
            hidden: [_activity('Hidden', applicationId: 'app-1')],
          ),
          _record(
            guildId: _atlas,
            processedAt: 5,
            hidden: [
              _activity('Hidden', applicationId: 'app-1'),
              _activity('Other', applicationId: 'app-2'),
            ],
          ),
        ]);

      final hidden = store.presenceFor(_mira)!.hiddenActivities;
      expect(hidden.map((activity) => activity.applicationId).toSet(), {
        'app-1',
        'app-2',
      });
      expect(hidden, hasLength(2));
    });

    test('PRESENCES_REPLACE clears the friend scope before refilling it', () {
      final store = DiscordPresenceStore()
        ..apply([_record(userId: _mira), _record(userId: _roman)]);

      final changed = store.replaceFriendScope([
        _record(userId: _roman, status: Presence.idle),
      ]);

      expect(changed[_mira]!.status, Presence.offline);
      expect(changed[_roman]!.status, Presence.idle);
      expect(store.presenceFor(_mira), isNull);
    });

    test('a friend-scope presence survives a guild going away', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(status: Presence.idle),
          _record(guildId: _forge, processedAt: 10),
        ]);

      final changed = store.removeGuild(_forge);

      expect(changed[_mira]!.status, Presence.idle);
      expect(store.presenceFor(_mira)!.status, Presence.idle);
      expect(store.removeGuild('no-such-guild'), isEmpty);
    });

    test('leaving a guild drops only that cell', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(guildId: _forge),
          _record(guildId: _atlas, status: Presence.idle, processedAt: 5),
        ]);

      final changed = store.removeMember(guildId: _atlas, userId: _mira);

      expect(changed[_mira]!.status, Presence.online);
      expect(store.removeMember(guildId: _atlas, userId: _roman), isEmpty);
      expect(store.removeMember(guildId: 'nope', userId: _mira), isEmpty);
    });

    test('leaving the last guild removes the user', () {
      final store = DiscordPresenceStore()..apply([_record(guildId: _forge)]);

      final changed = store.removeMember(guildId: _forge, userId: _mira);

      expect(changed[_mira]!.status, Presence.offline);
      expect(store.presenceFor(_mira), isNull);
    });

    test('clear empties the whole map', () {
      final store = DiscordPresenceStore()..apply([_record(guildId: _forge)]);

      store.clear();

      expect(store.presenceFor(_mira), isNull);
      expect(store.all, isEmpty);
    });

    test('publishes the winning scope client status', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(
            guildId: _forge,
            processedAt: 10,
            clientStatus: const {ClientPlatform.mobile: Presence.online},
          ),
        ]);

      expect(store.presenceFor(_mira)!.isMobileOnly, isTrue);
    });

    test(
      'a presence with an explicit guild wins over the scope it arrived in',
      () {
        final record = DiscordPresenceMapper.record({
          'user': {'id': _mira},
          'status': 'online',
          'guild_id': _atlas,
        }, guildId: _forge)!;

        expect(record.guildId, _atlas);
      },
    );
  });

  group('activity ordering', () {
    test('ranks custom status above competing, streaming and playing', () {
      final sorted = DiscordPresenceActivities.sorted([
        _activity('Game'),
        _activity('Match', type: ActivityType.competing),
        _activity('Note', type: ActivityType.customStatus),
        _activity('Stream', type: ActivityType.streaming),
        _activity('Hang', type: ActivityType.hangStatus),
      ]);

      expect(sorted.map((activity) => activity.name), [
        'Note',
        'Match',
        'Stream',
        'Game',
        'Hang',
      ]);
    });

    test('rich presence outranks a bare activity of the same type', () {
      final sorted = DiscordPresenceActivities.sorted([
        _activity('Plain'),
        _activity('Rich', details: 'In a dungeon'),
      ]);

      expect(sorted.first.name, 'Rich');
    });

    test('the newest activity leads when rank and richness tie', () {
      final sorted = DiscordPresenceActivities.sorted([
        _activity('Older', createdAt: 100),
        _activity('Newer', createdAt: 900),
      ]);

      expect(sorted.first.name, 'Newer');
    });

    test('a single-entry list is handed back untouched', () {
      final one = [_activity('Only')];

      expect(identical(DiscordPresenceActivities.sorted(one), one), isTrue);
    });

    test('ranks every unlisted type at zero', () {
      expect(DiscordPresenceActivities.rankOf(ActivityType.watching), 0);
      expect(DiscordPresenceActivities.rankOf(ActivityType.listening), 0);
      expect(DiscordPresenceActivities.rankOf(ActivityType.playing), 1);
    });

    test('hidden dedupe keeps the first entry per application and party', () {
      final deduped = DiscordPresenceActivities.dedupeHidden([
        _activity('First', applicationId: 'app-1', partyId: 'p'),
        _activity('Second', applicationId: 'app-1', partyId: 'p'),
        _activity('Third', applicationId: 'app-2'),
      ]);

      expect(deduped.map((activity) => activity.name), ['Third', 'First']);
    });

    test('hidden dedupe leaves a short list alone', () {
      final one = [_activity('Only')];

      expect(
        identical(DiscordPresenceActivities.dedupeHidden(one), one),
        isTrue,
      );
    });

    test('collapses two PLAYING entries down to the best one', () {
      final filtered = DiscordPresenceActivities.filterDuplicatePlaying([
        _activity('Detected'),
        _activity('Rich', details: 'Chapter 3'),
        _activity('Note', type: ActivityType.customStatus),
      ]);

      expect(filtered.map((activity) => activity.name), ['Note', 'Rich']);
    });

    test('leaves a list with one PLAYING entry as it is', () {
      final list = [
        _activity('Only'),
        _activity('Note', type: ActivityType.customStatus),
      ];

      expect(
        identical(DiscordPresenceActivities.filterDuplicatePlaying(list), list),
        isTrue,
      );
    });

    test('the store applies the duplicate filter when it publishes', () {
      final store = DiscordPresenceStore()
        ..apply([
          _record(
            guildId: _forge,
            activities: [
              _activity('Elden Ring'),
              _activity('Elden Ring', details: 'Limgrave'),
            ],
          ),
        ]);

      final activities = store.presenceFor(_mira)!.activities;
      expect(activities, hasLength(1));
      expect(activities.single.details, 'Limgrave');
    });
  });
}
