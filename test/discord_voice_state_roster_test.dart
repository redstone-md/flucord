import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_voice_state_roster.dart';

void main() {
  test('seats the occupants a GUILD_CREATE announces', () {
    final roster = DiscordVoiceStateRoster();

    final applied = roster.accept(
      eventName: 'GUILD_CREATE',
      data: const {
        'id': 'guild-1',
        'voice_states': [
          {
            'user_id': 'member-1',
            'channel_id': 'voice-1',
            'self_mute': true,
            'self_deaf': true,
            'mute': true,
            'deaf': true,
            'self_stream': true,
            'self_video': true,
          },
          {'user_id': 'member-2', 'channel_id': 'voice-2'},
        ],
      },
    );

    expect(applied.map((state) => state.userId), ['member-1', 'member-2']);
    final seated = roster.participantsIn(
      guildId: 'guild-1',
      channelId: 'voice-1',
    );
    expect(seated.single.userId, 'member-1');
    expect(seated.single.guildId, 'guild-1');
    expect(seated.single.selfMuted, isTrue);
    expect(seated.single.selfDeafened, isTrue);
    expect(seated.single.serverMuted, isTrue);
    expect(seated.single.serverDeafened, isTrue);
    expect(seated.single.isStreaming, isTrue);
    expect(seated.single.isVideoEnabled, isTrue);

    final other = roster.participantsIn(
      guildId: 'guild-1',
      channelId: 'voice-2',
    );
    expect(other.single.userId, 'member-2');
    expect(other.single.selfMuted, isFalse);
    expect(other.single.isVideoEnabled, isFalse);
  });

  test('replaces a guild snapshot instead of merging it', () {
    final roster = DiscordVoiceStateRoster()
      ..accept(
        eventName: 'GUILD_CREATE',
        data: const {
          'id': 'guild-1',
          'voice_states': [
            {'user_id': 'member-1', 'channel_id': 'voice-1'},
            {'user_id': 'member-2', 'channel_id': 'voice-1'},
          ],
        },
      );

    // A reconnect replays GUILD_CREATE; member-2 left while the socket was
    // down, so no VOICE_STATE_UPDATE ever announced the departure.
    roster.accept(
      eventName: 'GUILD_CREATE',
      data: const {
        'id': 'guild-1',
        'voice_states': [
          {'user_id': 'member-1', 'channel_id': 'voice-1'},
        ],
      },
    );

    expect(
      roster
          .participantsIn(guildId: 'guild-1', channelId: 'voice-1')
          .map((state) => state.userId),
      ['member-1'],
    );
  });

  test('accepts a guild with no voice states at all', () {
    final roster = DiscordVoiceStateRoster();

    expect(
      roster.accept(eventName: 'GUILD_CREATE', data: const {'id': 'guild-1'}),
      isEmpty,
    );
    expect(
      roster.participantsIn(guildId: 'guild-1', channelId: 'voice-1'),
      isEmpty,
    );
  });

  test('ignores a GUILD_CREATE that cannot be attributed to a guild', () {
    final roster = DiscordVoiceStateRoster();
    const states = [
      {'user_id': 'member-1', 'channel_id': 'voice-1'},
    ];

    expect(
      roster.accept(
        eventName: 'GUILD_CREATE',
        data: const {'voice_states': states},
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'GUILD_CREATE',
        data: const {'id': '', 'voice_states': states},
      ),
      isEmpty,
    );
  });

  test('adds a live voice state and clears the seat on departure', () {
    final roster = DiscordVoiceStateRoster();

    roster.accept(
      eventName: 'VOICE_STATE_UPDATE',
      data: const {
        'guild_id': 'guild-1',
        'user_id': 'member-1',
        'channel_id': 'voice-1',
      },
    );
    expect(
      roster.participantsIn(guildId: 'guild-1', channelId: 'voice-1'),
      hasLength(1),
    );

    final departure = roster.accept(
      eventName: 'VOICE_STATE_UPDATE',
      data: const {
        'guild_id': 'guild-1',
        'user_id': 'member-1',
        'channel_id': null,
      },
    );

    expect(departure.single.channelId, isNull);
    expect(
      roster.participantsIn(guildId: 'guild-1', channelId: 'voice-1'),
      isEmpty,
    );
  });

  test('applies every state a VOICE_STATE_UPDATE_BATCH carries', () {
    final roster = DiscordVoiceStateRoster();

    final applied = roster.accept(
      eventName: 'VOICE_STATE_UPDATE_BATCH',
      data: const {
        'voice_states': [
          {
            'guild_id': 'guild-1',
            'user_id': 'member-1',
            'channel_id': 'voice-1',
          },
          {
            'guild_id': 'guild-1',
            'user_id': 'member-2',
            'channel_id': 'voice-1',
          },
        ],
      },
    );

    expect(applied, hasLength(2));
    expect(
      roster.participantsIn(guildId: 'guild-1', channelId: 'voice-1'),
      hasLength(2),
    );
  });

  test('drops dispatches and rows it cannot read', () {
    final roster = DiscordVoiceStateRoster();

    expect(
      roster.accept(eventName: 'MESSAGE_CREATE', data: const {'id': 'm-1'}),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE_BATCH',
        data: const {'voice_states': 'not-a-list'},
      ),
      isEmpty,
    );
    // A DM call state: no guild, so it belongs to the call surface.
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'member-1', 'channel_id': 'dm-1'},
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {
          'guild_id': 'guild-1',
          'user_id': 7,
          'channel_id': 'voice-1',
        },
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {
          'guild_id': 'guild-1',
          'user_id': 'member-1',
          'channel_id': 7,
        },
      ),
      isEmpty,
    );
  });

  test('forgets every guild on clearAll', () {
    final roster = DiscordVoiceStateRoster()
      ..accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {
          'guild_id': 'guild-1',
          'user_id': 'member-1',
          'channel_id': 'voice-1',
        },
      )
      ..clearAll();

    expect(
      roster.participantsIn(guildId: 'guild-1', channelId: 'voice-1'),
      isEmpty,
    );
  });
  _regressions();
}

void _regressions() {
  group('roster regressions', () {
    Map<String, Object?> state(String userId, String? channelId) => {
      'user_id': userId,
      'guild_id': 'guild',
      'channel_id': channelId,
      'self_mute': false,
      'self_deaf': false,
      'mute': false,
      'deaf': false,
      'self_stream': false,
      'self_video': false,
    };

    test('a snapshot reports whoever it no longer seats', () {
      final roster = DiscordVoiceStateRoster()
        ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('a', 'room'))
        ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('b', 'room'));

      // GUILD_CREATE is the only notice that 'b' left while the socket was
      // down, so it has to surface as a departure rather than a silent wipe.
      final events = roster.accept(
        eventName: 'GUILD_CREATE',
        data: {
          'id': 'guild',
          'voice_states': [state('a', 'room')],
        },
      );

      final departed = events.where((event) => event.channelId == null);
      expect(departed.map((event) => event.userId), ['b']);
      expect(
        roster
            .participantsIn(guildId: 'guild', channelId: 'room')
            .map((event) => event.userId),
        ['a'],
      );
    });

    test('a replayed READY empties the roster', () {
      final roster = DiscordVoiceStateRoster()
        ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('a', 'room'));

      final events = roster.accept(
        eventName: 'READY',
        data: const {'user': <String, Object?>{}},
      );

      expect(events.single.userId, 'a');
      expect(events.single.channelId, isNull);
      expect(
        roster.participantsIn(guildId: 'guild', channelId: 'room'),
        isEmpty,
      );
    });

    test('a departure for an unknown guild leaves no empty bucket', () {
      final roster = DiscordVoiceStateRoster()
        ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('a', null));

      expect(
        roster.participantsIn(guildId: 'guild', channelId: 'room'),
        isEmpty,
      );
    });
  });
}
