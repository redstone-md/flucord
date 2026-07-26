import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_call_state_roster.dart';
import 'package:flucord/src/data/discord/discord_voice_state_reader.dart';

void main() {
  test('seats the occupants a CALL_CREATE announces', () {
    final roster = DiscordCallStateRoster();

    final changes = roster.accept(
      eventName: 'CALL_CREATE',
      data: const {
        'channel_id': 'dm-1',
        'voice_states': [
          {
            'user_id': 'member-1',
            'self_mute': true,
            'self_deaf': true,
            'mute': true,
            'deaf': true,
            'self_stream': true,
            'self_video': true,
          },
          {'user_id': 'member-2', 'channel_id': 'dm-1'},
        ],
      },
    );

    expect(changes.map((change) => change.state.userId), [
      'member-1',
      'member-2',
    ]);
    expect(changes.every((change) => change.channelId == 'dm-1'), isTrue);
    final seated = roster.participantsIn('dm-1');
    expect(seated.map((state) => state.userId), ['member-1', 'member-2']);
    // R08 forces guild_id to null inside CALL_CREATE; the seat inherits the
    // call's own channel when the state omits one.
    expect(seated.first.guildId, isNull);
    expect(seated.first.channelId, 'dm-1');
    expect(seated.first.selfMuted, isTrue);
    expect(seated.first.selfDeafened, isTrue);
    expect(seated.first.serverMuted, isTrue);
    expect(seated.first.serverDeafened, isTrue);
    expect(seated.first.isStreaming, isTrue);
    expect(seated.first.isVideoEnabled, isTrue);
    expect(seated.last.selfMuted, isFalse);
  });

  test('a CALL_CREATE snapshot reports whoever it no longer seats', () {
    final roster = DiscordCallStateRoster()
      ..accept(
        eventName: 'CALL_CREATE',
        data: const {
          'channel_id': 'dm-1',
          'voice_states': [
            {'user_id': 'member-1'},
            {'user_id': 'member-2'},
          ],
        },
      );

    final changes = roster.accept(
      eventName: 'CALL_CREATE',
      data: const {
        'channel_id': 'dm-1',
        'voice_states': [
          {'user_id': 'member-1'},
        ],
      },
    );

    final departed = changes.where((change) => change.state.channelId == null);
    expect(departed.map((change) => change.state.userId), ['member-2']);
    expect(roster.participantsIn('dm-1').map((state) => state.userId), [
      'member-1',
    ]);
  });

  test('a live voice state seats and a null channel vacates', () {
    final roster = DiscordCallStateRoster();

    roster.accept(
      eventName: 'VOICE_STATE_UPDATE',
      data: const {'user_id': 'member-1', 'channel_id': 'dm-1'},
    );
    expect(roster.participantsIn('dm-1'), hasLength(1));

    // The departure names neither guild nor channel, so the seat is only
    // findable through the channel the roster last saw this user in.
    final changes = roster.accept(
      eventName: 'VOICE_STATE_UPDATE',
      data: const {'user_id': 'member-1', 'channel_id': null},
    );

    expect(changes.single.channelId, 'dm-1');
    expect(changes.single.state.channelId, isNull);
    expect(roster.participantsIn('dm-1'), isEmpty);
  });

  test('a departure for somebody who was never seated changes nothing', () {
    final roster = DiscordCallStateRoster();

    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'member-1', 'channel_id': null},
      ),
      isEmpty,
    );
  });

  test('moving between calls vacates the seat that was left', () {
    final roster = DiscordCallStateRoster()
      ..accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'member-1', 'channel_id': 'dm-1'},
      );

    final changes = roster.accept(
      eventName: 'VOICE_STATE_UPDATE',
      data: const {'user_id': 'member-1', 'channel_id': 'dm-2'},
    );

    expect(changes.first.channelId, 'dm-1');
    expect(changes.first.state.channelId, isNull);
    expect(changes.last.channelId, 'dm-2');
    expect(roster.participantsIn('dm-1'), isEmpty);
    expect(roster.participantsIn('dm-2'), hasLength(1));
  });

  test('applies every state a VOICE_STATE_UPDATE_BATCH carries', () {
    final roster = DiscordCallStateRoster();

    final changes = roster.accept(
      eventName: 'VOICE_STATE_UPDATE_BATCH',
      data: const {
        'voice_states': [
          {'user_id': 'member-1', 'channel_id': 'dm-1'},
          {'user_id': 'member-2', 'channel_id': 'dm-1'},
          // Guild voice rides the same dispatch and belongs to the other store.
          {'user_id': 'member-3', 'guild_id': 'guild-1', 'channel_id': 'v-1'},
        ],
      },
    );

    expect(changes, hasLength(2));
    expect(roster.participantsIn('dm-1'), hasLength(2));
  });

  test('CALL_DELETE empties the call', () {
    final roster = DiscordCallStateRoster()
      ..accept(
        eventName: 'CALL_CREATE',
        data: const {
          'channel_id': 'dm-1',
          'voice_states': [
            {'user_id': 'member-1'},
          ],
        },
      );

    final changes = roster.accept(
      eventName: 'CALL_DELETE',
      data: const {'channel_id': 'dm-1'},
    );

    expect(changes.single.channelId, 'dm-1');
    expect(changes.single.state.channelId, isNull);
    expect(roster.participantsIn('dm-1'), isEmpty);
    // The same user may now rejoin without the stale seat interfering.
    roster.accept(
      eventName: 'VOICE_STATE_UPDATE',
      data: const {'user_id': 'member-1', 'channel_id': 'dm-1'},
    );
    expect(roster.participantsIn('dm-1'), hasLength(1));
  });

  test('a replayed READY empties every call', () {
    final roster = DiscordCallStateRoster()
      ..accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'member-1', 'channel_id': 'dm-1'},
      );

    final changes = roster.accept(
      eventName: 'READY',
      data: const {'user': <String, Object?>{}},
    );

    expect(changes.single.state.userId, 'member-1');
    expect(changes.single.state.channelId, isNull);
    expect(roster.participantsIn('dm-1'), isEmpty);
  });

  test('drops dispatches and rows it cannot read', () {
    final roster = DiscordCallStateRoster();

    expect(
      roster.accept(eventName: 'MESSAGE_CREATE', data: const {'id': 'm-1'}),
      isEmpty,
    );
    expect(roster.accept(eventName: 'CALL_CREATE', data: const {}), isEmpty);
    expect(
      roster.accept(eventName: 'CALL_CREATE', data: const {'channel_id': ''}),
      isEmpty,
    );
    expect(
      roster.accept(eventName: 'CALL_DELETE', data: const {'channel_id': 7}),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'CALL_DELETE',
        data: const {'channel_id': 'unknown'},
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE_BATCH',
        data: const {'voice_states': 'not-a-list'},
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 7, 'channel_id': 'dm-1'},
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': '', 'channel_id': 'dm-1'},
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'member-1', 'channel_id': 7},
      ),
      isEmpty,
    );
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {
          'user_id': 'member-1',
          'guild_id': '',
          'channel_id': 'dm-1',
        },
      ),
      isEmpty,
    );
  });

  test('clearAll forgets every call and the seats behind it', () {
    final roster = DiscordCallStateRoster()
      ..accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'member-1', 'channel_id': 'dm-1'},
      )
      ..clearAll();

    expect(roster.participantsIn('dm-1'), isEmpty);
    // The user table went with it, so a later departure finds nothing to undo.
    expect(
      roster.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'member-1', 'channel_id': null},
      ),
      isEmpty,
    );
  });

  test('bounds a voice state list that arrived off the wire', () {
    final states = [
      for (
        var index = 0;
        index < DiscordVoiceStateReader.maxStatesPerFrame + 5;
        index++
      )
        {'user_id': 'member-$index', 'channel_id': 'dm-1'},
    ];

    final roster = DiscordCallStateRoster()
      ..accept(
        eventName: 'CALL_CREATE',
        data: {'channel_id': 'dm-1', 'voice_states': states},
      );

    expect(
      roster.participantsIn('dm-1'),
      hasLength(DiscordVoiceStateReader.maxStatesPerFrame),
    );
  });
}
