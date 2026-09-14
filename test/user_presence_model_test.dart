import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _mira = '222222222222222222';
const _roman = '333333333333333333';

const _member = Member(
  id: _mira,
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Product design',
  presence: Presence.offline,
  colorValue: 0xff665f82,
);

ChatWorkspace _workspace() => ChatWorkspace(
  spaces: const [],
  channels: const [],
  members: const [
    _member,
    Member(
      id: _roman,
      displayName: 'Roman Vale',
      initials: 'RV',
      role: 'Infrastructure',
      presence: Presence.offline,
      colorValue: 0xff506674,
    ),
  ],
  messages: const [],
  currentMemberId: _mira,
);

void main() {
  group('status enum', () {
    test('maps every wire value and falls back to unknown', () {
      expect(Presence.fromWire('online'), Presence.online);
      expect(Presence.fromWire('idle'), Presence.idle);
      expect(Presence.fromWire('dnd'), Presence.doNotDisturb);
      expect(Presence.fromWire('offline'), Presence.offline);
      expect(Presence.fromWire('invisible'), Presence.invisible);
      expect(Presence.fromWire('streaming'), Presence.streaming);
      expect(Presence.fromWire('elsewhere'), Presence.unknown);
      expect(Presence.fromWire(null), Presence.unknown);
    });

    test('keeps the ordinals the member cache has already written', () {
      expect(Presence.online.index, 0);
      expect(Presence.idle.index, 1);
      expect(Presence.offline.index, 2);
    });

    test('counts only the four connected statuses as online', () {
      expect(Presence.online.isOnline, isTrue);
      expect(Presence.idle.isOnline, isTrue);
      expect(Presence.doNotDisturb.isOnline, isTrue);
      expect(Presence.streaming.isOnline, isTrue);
      expect(Presence.offline.isOnline, isFalse);
      expect(Presence.invisible.isOnline, isFalse);
      expect(Presence.unknown.isOnline, isFalse);
    });

    test('names every status for the picker and the profile', () {
      for (final status in Presence.values) {
        expect(status.label, isNotEmpty);
      }
      expect(Presence.doNotDisturb.label, 'Do Not Disturb');
      expect(Presence.selectable, [
        Presence.online,
        Presence.idle,
        Presence.doNotDisturb,
        Presence.invisible,
      ]);
    });
  });

  group('activity', () {
    test('summarises each type with its verb', () {
      expect(
        const UserActivity(name: 'Elden Ring').summary,
        'Playing Elden Ring',
      );
      expect(
        const UserActivity(
          name: 'Twitch',
          type: ActivityType.streaming,
        ).summary,
        'Streaming Twitch',
      );
      expect(
        const UserActivity(
          name: 'Spotify',
          type: ActivityType.listening,
        ).summary,
        'Listening to Spotify',
      );
      expect(
        const UserActivity(name: 'A film', type: ActivityType.watching).summary,
        'Watching A film',
      );
      expect(
        const UserActivity(name: 'A cup', type: ActivityType.competing).summary,
        'Competing in A cup',
      );
      expect(
        const UserActivity(
          name: 'Custom Status',
          type: ActivityType.customStatus,
          state: 'Heads down',
        ).summary,
        'Heads down',
      );
      expect(
        const UserActivity(
          name: 'Chilling',
          type: ActivityType.hangStatus,
        ).summary,
        'Chilling',
      );
      expect(
        const UserActivity(
          name: 'Custom Status',
          type: ActivityType.customStatus,
        ).summary,
        '',
      );
    });

    test('status_display_type promotes the line Discord asks for', () {
      const activity = UserActivity(
        name: 'Spotify',
        type: ActivityType.listening,
        state: 'Some Artist',
        details: 'Some Track',
      );

      expect(activity.summary, 'Listening to Spotify');
      expect(
        UserActivity(
          name: activity.name,
          type: activity.type,
          state: activity.state,
          details: activity.details,
          statusDisplayType: StatusDisplayType.state,
        ).summary,
        'Listening to Some Artist',
      );
      expect(
        UserActivity(
          name: activity.name,
          type: activity.type,
          state: activity.state,
          details: activity.details,
          statusDisplayType: StatusDisplayType.details,
        ).summary,
        'Listening to Some Track',
      );
    });

    test('an empty promoted line falls back to the name', () {
      expect(
        const UserActivity(
          name: 'Spotify',
          type: ActivityType.listening,
          state: '',
          statusDisplayType: StatusDisplayType.state,
        ).summary,
        'Listening to Spotify',
      );
    });

    test('recognises rich presence by any of its five markers', () {
      expect(const UserActivity(name: 'Plain').isRichPresence, isFalse);
      expect(
        const UserActivity(name: 'x', details: 'y').isRichPresence,
        isTrue,
      );
      expect(const UserActivity(name: 'x', state: 'y').isRichPresence, isTrue);
      expect(
        const UserActivity(
          name: 'x',
          party: ActivityParty(id: 'p'),
        ).isRichPresence,
        isTrue,
      );
      expect(
        const UserActivity(
          name: 'x',
          secrets: ActivitySecrets(join: 'j'),
        ).isRichPresence,
        isTrue,
      );
      expect(
        const UserActivity(
          name: 'x',
          assets: ActivityAssets(largeImage: 'a'),
        ).isRichPresence,
        isTrue,
      );
      expect(
        const UserActivity(
          name: 'x',
          assets: ActivityAssets(smallText: 'a'),
        ).isRichPresence,
        isTrue,
      );
      expect(
        const UserActivity(
          name: 'x',
          assets: ActivityAssets(largeText: 'a'),
        ).isRichPresence,
        isFalse,
      );
      expect(
        const UserActivity(
          name: 'x',
          details: 'y',
          type: ActivityType.customStatus,
        ).isRichPresence,
        isFalse,
      );
    });

    test('measures elapsed and remaining time, never negative', () {
      final now = DateTime.utc(2026, 7, 26, 12);
      final stamps = ActivityTimestamps(
        startMs: now.millisecondsSinceEpoch - 90000,
        endMs: now.millisecondsSinceEpoch + 30000,
      );

      expect(stamps.elapsedAt(now), const Duration(seconds: 90));
      expect(stamps.remainingAt(now), const Duration(seconds: 30));
      expect(stamps.isEmpty, isFalse);

      final past = ActivityTimestamps(
        startMs: now.millisecondsSinceEpoch + 1000,
        endMs: now.millisecondsSinceEpoch - 1000,
      );
      expect(past.elapsedAt(now), Duration.zero);
      expect(past.remainingAt(now), Duration.zero);

      const empty = ActivityTimestamps();
      expect(empty.elapsedAt(now), isNull);
      expect(empty.remainingAt(now), isNull);
      expect(empty.isEmpty, isTrue);
    });

    test('asset and party helpers describe what they carry', () {
      expect(const ActivityAssets().isEmpty, isTrue);
      expect(const ActivityAssets(largeText: 'x').isEmpty, isFalse);
      expect(const ActivityAssets(largeUrl: 'x').isEmpty, isFalse);
      expect(const ActivityAssets(smallImage: 'x').isEmpty, isFalse);
      expect(const ActivityAssets(smallUrl: 'x').isEmpty, isFalse);
      expect(const ActivityAssets(smallText: 'x').isEmpty, isFalse);
      expect(const ActivityParty(currentSize: 1, maxSize: 2).hasSize, isTrue);
      expect(const ActivityParty(currentSize: 1).hasSize, isFalse);
      expect(const ActivityEmoji(name: 'x', id: '').isCustom, isFalse);
      expect(ActivityType.fromWire(1).wireValue, 1);
      expect(StatusDisplayType.fromWire(0), StatusDisplayType.name);
      expect(StatusDisplayType.details.wireValue, 2);
      expect(ActivityPartyPrivacy.public.wireValue, 1);
      expect(ClientPlatform.fromWire('web'), ClientPlatform.web);
      expect(ClientPlatform.vr.wireValue, 'vr');
    });
  });

  group('user presence', () {
    const custom = UserActivity(
      name: 'Custom Status',
      type: ActivityType.customStatus,
      state: 'Heads down',
    );
    const game = UserActivity(name: 'Elden Ring', details: 'Limgrave');
    const hang = UserActivity(name: 'Chilling', type: ActivityType.hangStatus);

    test('picks the primary activity over the custom status', () {
      const presence = UserPresence(activities: [custom, game]);

      expect(presence.primaryActivity, game);
      expect(presence.customStatus, custom);
      expect(presence.richActivity, game);
    });

    test('falls back to the custom status when nothing else is happening', () {
      const presence = UserPresence(activities: [hang, custom]);

      expect(presence.primaryActivity, custom);
      expect(presence.richActivity, isNull);
    });

    test('has no primary activity at all when the list is empty', () {
      expect(const UserPresence().primaryActivity, isNull);
      expect(const UserPresence().customStatus, isNull);
      expect(const UserPresence(activities: [hang]).primaryActivity, isNull);
      expect(
        const UserPresence(
          activities: [UserActivity(name: 'Plain')],
        ).richActivity,
        isNull,
      );
    });

    test('synthesises the streaming status from the activity list', () {
      const streaming = UserPresence(
        status: Presence.online,
        activities: [UserActivity(name: 'x', type: ActivityType.streaming)],
      );

      expect(streaming.isStreaming, isTrue);
      expect(streaming.displayStatus, Presence.streaming);
      expect(
        const UserPresence(
          status: Presence.offline,
          activities: [UserActivity(name: 'x', type: ActivityType.streaming)],
        ).displayStatus,
        Presence.offline,
      );
      expect(const UserPresence().displayStatus, Presence.offline);
    });

    test('reads the mobile and VR flags out of the client status map', () {
      const mobile = UserPresence(
        clientStatus: {ClientPlatform.mobile: Presence.online},
      );
      expect(mobile.isMobileOnly, isTrue);
      expect(mobile.isVrOnline, isFalse);

      expect(
        const UserPresence(
          clientStatus: {
            ClientPlatform.mobile: Presence.online,
            ClientPlatform.desktop: Presence.online,
          },
        ).isMobileOnly,
        isFalse,
      );
      expect(
        const UserPresence(
          clientStatus: {
            ClientPlatform.mobile: Presence.online,
            ClientPlatform.vr: Presence.online,
          },
        ).isMobileOnly,
        isFalse,
      );
      expect(
        const UserPresence(
          clientStatus: {ClientPlatform.vr: Presence.online},
        ).isVrOnline,
        isTrue,
      );
    });

    test('describes itself as empty only when nothing is known', () {
      expect(UserPresence.offline.isEmpty, isTrue);
      expect(const UserPresence(status: Presence.online).isEmpty, isFalse);
      expect(const UserPresence(activities: [game]).isEmpty, isFalse);
      expect(const UserPresence(hiddenActivities: [game]).isEmpty, isFalse);
    });

    test('copies one field at a time', () {
      const presence = UserPresence(status: Presence.idle);

      expect(
        presence.copyWith(status: Presence.online).status,
        Presence.online,
      );
      expect(presence.copyWith().status, Presence.idle);
      expect(presence.copyWith(activities: const [game]).activities, [game]);
      expect(
        presence.copyWith(hiddenActivities: const [game]).hiddenActivities,
        [game],
      );
      expect(
        presence
            .copyWith(clientStatus: const {ClientPlatform.web: Presence.online})
            .clientStatus,
        isNotEmpty,
      );
    });
  });

  group('workspace', () {
    test('applies a presence and keeps the coarse status in step', () {
      final workspace = _workspace().applyPresence(
        _mira,
        const UserPresence(
          status: Presence.doNotDisturb,
          activities: [UserActivity(name: 'Elden Ring')],
        ),
      );

      final member = workspace.memberById(_mira);
      expect(member.presence, Presence.doNotDisturb);
      expect(member.presenceDetail!.primaryActivity!.name, 'Elden Ring');
      expect(workspace.memberById(_roman).presenceDetail, isNull);
    });

    test('a batch touches only the members it names', () {
      final workspace = _workspace().applyPresences(const {
        _roman: UserPresence(status: Presence.idle),
        'someone-else': UserPresence(status: Presence.online),
      });

      expect(workspace.memberById(_roman).presence, Presence.idle);
      expect(workspace.memberById(_mira).presence, Presence.offline);
    });

    test('a batch that changes nothing returns the same workspace', () {
      final workspace = _workspace();

      expect(identical(workspace.applyPresences(const {}), workspace), isTrue);
      expect(
        identical(
          workspace.applyPresences(const {
            'nobody': UserPresence(status: Presence.online),
          }),
          workspace,
        ),
        isTrue,
      );
    });

    test('re-mapping a member never erases the presence already reported', () {
      final workspace = _workspace()
          .applyPresence(_mira, const UserPresence(status: Presence.online))
          .upsertMember(_member);

      expect(workspace.memberById(_mira).presenceDetail, isNotNull);
      expect(workspace.memberById(_mira).presence, Presence.online);
    });

    test(
      'a member with no presence reported falls back to its cached status',
      () {
        const member = Member(
          id: _mira,
          displayName: 'Mira',
          initials: 'MC',
          role: 'Member',
          presence: Presence.idle,
          colorValue: 0,
        );

        expect(member.presenceOrCoarse.status, Presence.idle);
        expect(
          member
              .withPresence(const UserPresence(status: Presence.doNotDisturb))
              .presenceOrCoarse
              .status,
          Presence.doNotDisturb,
        );
        expect(
          member
              .copyWith(
                presenceDetail: const UserPresence(status: Presence.online),
              )
              .presenceDetail!
              .status,
          Presence.online,
        );
      },
    );
  });

  group('session', () {
    test('defaults everything a bare session leaves out', () {
      const session = UserSession(sessionId: 'a');

      expect(session.status, Presence.offline);
      expect(session.lastModified, 0);
      expect(session.active, isFalse);
      expect(session.activities, isEmpty);
      expect(session.hiddenActivities, isEmpty);
      expect(session.operatingSystem, isNull);
    });
  });

  group('self presence', () {
    test('copies one field at a time', () {
      const presence = SelfPresence();

      expect(presence.copyWith(status: Presence.idle).status, Presence.idle);
      expect(presence.copyWith(since: 5).since, 5);
      expect(presence.copyWith(afk: true).afk, isTrue);
      expect(
        presence
            .copyWith(activities: const [UserActivity(name: 'x')])
            .activities,
        hasLength(1),
      );
      expect(presence.copyWith().status, Presence.online);
    });
  });
}
