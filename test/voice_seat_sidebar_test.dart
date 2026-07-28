import 'package:flucord/src/data/discord/discord_voice_state_roster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> state(String userId, String channelId) => {
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

  test('reports who is seated in channels nobody joined from here', () {
    // The sidebar shows a voice channel's occupants without this client ever
    // connecting, which is how a user decides which room to walk into. Reading
    // it off the connection could only ever answer for the room we are in.
    final roster = DiscordVoiceStateRoster()
      ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('a', 'room-1'))
      ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('b', 'room-1'))
      ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('c', 'room-2'));

    final seated = roster.seatedByChannel;

    expect(seated.keys.toSet(), {'room-1', 'room-2'});
    expect(seated['room-1']!.map((s) => s.userId).toSet(), {'a', 'b'});
    expect(seated['room-2']!.single.userId, 'c');
  });

  test('a departure empties the channel it left', () {
    final roster = DiscordVoiceStateRoster()
      ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('a', 'room-1'));

    roster.accept(
      eventName: 'VOICE_STATE_UPDATE',
      data: {...state('a', 'room-1'), 'channel_id': null},
    );

    expect(roster.seatedByChannel, isEmpty);
  });

  test('moving between channels seats the user only once', () {
    final roster = DiscordVoiceStateRoster()
      ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('a', 'room-1'))
      ..accept(eventName: 'VOICE_STATE_UPDATE', data: state('a', 'room-2'));

    final seated = roster.seatedByChannel;

    expect(seated.containsKey('room-1'), isFalse);
    expect(seated['room-2']!.single.userId, 'a');
  });
}
