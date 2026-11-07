import 'package:flucord/src/application/voice_sound_cues.dart';
import 'package:flucord/src/domain/client_sounds.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _room = VoiceSoundSnapshot(
  channelId: 'voice-1',
  connected: true,
  others: {'friend-1'},
  selfSeatedIn: 'voice-1',
);

void main() {
  group('the account itself', () {
    test('joining plays the join sound, leaving the disconnect sound', () {
      expect(
        voiceSoundBetween(VoiceSoundSnapshot.idle, _room),
        ClientSound.userJoin,
      );
      expect(
        voiceSoundBetween(_room, VoiceSoundSnapshot.idle),
        ClientSound.disconnect,
      );
    });

    test('still joining makes no sound yet', () {
      const joining = VoiceSoundSnapshot(channelId: 'voice-1');
      expect(voiceSoundBetween(VoiceSoundSnapshot.idle, joining), isNull);
      expect(voiceSoundBetween(joining, _room), ClientSound.userJoin);
    });

    test('walking into another channel plays the join sound', () {
      expect(
        voiceSoundBetween(_room, _room.copyWith(channelId: 'voice-2')),
        ClientSound.userJoin,
      );
    });

    test('a Stage makes no join or disconnect sound', () {
      final stage = _room.copyWith(isStage: true);
      expect(voiceSoundBetween(VoiceSoundSnapshot.idle, stage), isNull);
      expect(voiceSoundBetween(stage, VoiceSoundSnapshot.idle), isNull);
    });

    test('leaving clears mute and deafen without a sound for them', () {
      final deafened = _room.copyWith(muted: true, deafened: true);
      expect(
        voiceSoundBetween(deafened, VoiceSoundSnapshot.idle),
        ClientSound.disconnect,
      );
    });

    test('following a move to the new channel makes no second sound', () {
      final moved = _room.copyWith(selfSeatedIn: 'voice-2');
      final followed = moved.copyWith(channelId: 'voice-2', others: {});

      expect(voiceSoundBetween(_room, moved), ClientSound.userMoved);
      expect(voiceSoundBetween(moved, followed), isNull);
    });

    test('the room as it is on entry makes no join sound, even when the '
        'roster comes after the connection', () {
      const connected = VoiceSoundSnapshot(
        channelId: 'voice-1',
        connected: true,
      );
      final roster = connected.copyWith(
        others: {'friend-1', 'friend-2'},
        selfSeatedIn: 'voice-1',
      );

      expect(voiceSoundBetween(connected, roster), isNull);
      expect(
        voiceSoundBetween(roster, roster.copyWith(others: {'friend-1'})),
        ClientSound.userLeave,
      );
    });

    test('being moved by somebody else plays the moved sound', () {
      expect(
        voiceSoundBetween(_room, _room.copyWith(selfSeatedIn: 'voice-2')),
        ClientSound.userMoved,
      );
      // The account's own seat in the room it is in is no move.
      const unseated = VoiceSoundSnapshot(
        channelId: 'voice-1',
        connected: true,
      );
      expect(
        voiceSoundBetween(unseated, unseated.copyWith(selfSeatedIn: 'voice-1')),
        isNull,
      );
    });

    test('deafen wins over the mute that comes with it', () {
      expect(
        voiceSoundBetween(_room, _room.copyWith(muted: true, deafened: true)),
        ClientSound.deafen,
      );
      expect(
        voiceSoundBetween(_room.copyWith(muted: true, deafened: true), _room),
        ClientSound.undeafen,
      );
    });

    test('mute and unmute', () {
      final muted = _room.copyWith(muted: true);
      expect(voiceSoundBetween(_room, muted), ClientSound.mute);
      expect(voiceSoundBetween(muted, _room), ClientSound.unmute);
    });
  });

  group('the others in the room', () {
    test('somebody joining or leaving', () {
      final two = _room.copyWith(others: {'friend-1', 'friend-2'});
      expect(voiceSoundBetween(_room, two), ClientSound.userJoin);
      expect(voiceSoundBetween(two, _room), ClientSound.userLeave);
    });

    test('a crowd past 25 makes no join or leave sound', () {
      final crowd = _room.copyWith(
        others: {for (var i = 0; i < 26; i++) 'member-$i'},
      );
      final more = crowd.copyWith(others: {...crowd.others, 'late'});
      expect(voiceSoundBetween(crowd, more), isNull);
    });

    test('nobody else is heard on a Stage', () {
      final stage = _room.copyWith(isStage: true);
      final more = stage.copyWith(others: {'friend-1', 'friend-2'});
      expect(voiceSoundBetween(stage, more), isNull);
    });

    test('a Stream starting is heard by everybody in the room', () {
      expect(
        voiceSoundBetween(_room, _room.copyWith(streamers: {'friend-1'})),
        ClientSound.streamStarted,
      );
    });

    test('a Stream ending is heard by its watchers and its sender', () {
      final live = _room.copyWith(streamers: {'friend-1'});
      expect(voiceSoundBetween(live, _room), isNull);
      expect(
        voiceSoundBetween(live.copyWith(followed: {'friend-1'}), _room),
        ClientSound.streamEnded,
      );
    });
  });

  test('the cues play each change once, as the room notifies', () {
    final room = ValueNotifier(VoiceSoundSnapshot.idle);
    final sounds = _RecordingSounds();
    final cues = VoiceSoundCues(
      changes: room,
      read: () => room.value,
      sounds: sounds,
    );
    addTearDown(cues.dispose);

    room.value = _room;
    room.value = _room.copyWith(muted: true);
    // A notification with nothing new in it, as speaking flips make.
    room.value = _room.copyWith(muted: true);

    expect(sounds.played, [ClientSound.userJoin, ClientSound.mute]);
  });
}

final class _RecordingSounds implements ClientSoundPlayer {
  final List<ClientSound> played = [];

  @override
  void play(ClientSound sound) => played.add(sound);

  @override
  void loop(ClientSound sound) {}

  @override
  void stopLoop() {}
}
