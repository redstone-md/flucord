import 'package:flucord/src/application/active_friends.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

// Who the "Active now" column lists (FLUCORD-89).

const _guild = CommunitySpace(
  id: 'guild-1',
  name: 'Play&day',
  monogram: 'P&',
  colorValue: 0xff8a3a3a,
);

const _voice = ConversationChannel(
  id: 'voice-1',
  spaceId: 'guild-1',
  name: 'Lounge',
  topic: '',
  kind: ChannelKind.voice,
);

const _game = UserActivity(name: 'Dota 2');

const _custom = UserActivity(
  name: 'Custom Status',
  type: ActivityType.customStatus,
  state: 'Heads down',
);

Member _person(String id, {List<UserActivity> activities = const []}) => Member(
  id: id,
  displayName: id,
  initials: id.substring(0, 1),
  role: '',
  presence: Presence.online,
  colorValue: 0xff665f82,
  presenceDetail: UserPresence(status: Presence.online, activities: activities),
);

VoiceParticipantStateEvent _seat(String userId, {String? channelId}) =>
    VoiceParticipantStateEvent(
      userId: userId,
      guildId: _guild.id,
      channelId: channelId ?? _voice.id,
      selfMuted: false,
      selfDeafened: false,
      serverMuted: false,
      serverDeafened: false,
      isStreaming: false,
      isVideoEnabled: false,
    );

List<DiscordRelationshipUser> _friends(List<String> ids) => [
  for (final id in ids)
    DiscordRelationshipUser(
      id: id,
      displayName: id,
      status: DiscordPresenceStatus.idle,
    ),
];

ChatWorkspace _workspace(List<Member> members) => ChatWorkspace(
  spaces: const [_guild],
  channels: const [_voice],
  members: members,
  messages: const [],
  currentMemberId: 'me',
);

void main() {
  test('lists friends who are doing something or sitting in voice', () {
    final workspace = _workspace([
      _person('gamer', activities: const [_game, _custom]),
      _person('talker'),
      _person('quiet', activities: const [_custom]),
      _person('stranger', activities: const [_game]),
      _person('other'),
    ]);

    final active = activeFriends(
      _friends(['gamer', 'talker', 'quiet']),
      workspace: workspace,
      seatedByChannel: {
        _voice.id: [_seat('talker'), _seat('other')],
      },
    );

    expect(active.map((friend) => friend.person.id), ['gamer', 'talker']);
    // A custom status is a sentence, not something being done.
    expect(active.first.doing, [_game]);
    expect(active.first.room, isNull);
    final room = active.last.room!;
    expect(room.channel, _voice);
    expect(room.space, _guild);
    expect(room.people.map((person) => person.id), ['talker', 'other']);
  });

  test('a seat in a channel this workspace does not know is no room', () {
    final active = activeFriends(
      _friends(['talker']),
      workspace: _workspace([_person('talker')]),
      seatedByChannel: {
        'unknown': [_seat('talker', channelId: 'unknown')],
      },
    );

    expect(active, isEmpty);
  });

  test('a friend in voice with no member row is still listed', () {
    final active = activeFriends(
      _friends(['talker']),
      workspace: _workspace(const []),
      seatedByChannel: {
        _voice.id: [_seat('talker')],
      },
    );

    final talker = active.single;
    expect(talker.person.id, 'talker');
    expect(talker.person.displayName, 'talker');
    expect(talker.person.presence, Presence.idle);
    expect(talker.room?.channel, _voice);
  });
}
