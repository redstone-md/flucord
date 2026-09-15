import 'package:flucord/src/data/windows_message_speech_player.dart';
import 'package:flucord/src/domain/soundboard_playback.dart';
import 'package:flutter_test/flutter_test.dart';

/// The synthesis half of spoken-aloud messages. A Windows runner carries the
/// real synthesiser, so the expectations branch on what the player reports:
/// where it can speak it proves the handoff to the media playback layer,
/// and where it cannot it proves the plain refusal.
void main() {
  test('the refusal and the handoff follow what the machine supports',
      () async {
    final sounds = _RecordingSounds();
    final speech = WindowsMessageSpeechPlayer(player: sounds);

    final spoken = await speech.speak('The release is out.');

    if (speech.isSupported) {
      // A synthesiser is here: the message goes out as a spoken file handed
      // to the media playback layer.
      expect(spoken, isTrue);
      expect(sounds.played, hasLength(1));
    } else {
      // No synthesiser: the contract's answer is a plain refusal, not an
      // error and not a silent pretence.
      expect(spoken, isFalse);
      expect(sounds.played, isEmpty);
      expect(await speech.speak('The release is out.'), isFalse);
    }
  });

  test('empty text is refused rather than spoken as silence', () async {
    final sounds = _RecordingSounds();
    final speech = WindowsMessageSpeechPlayer(player: sounds);

    final spoken = await speech.speak('   ');

    expect(spoken, isFalse);
    expect(sounds.played, isEmpty);
  });
}

final class _RecordingSounds implements SoundboardAudioPlayer {
  final List<String> played = [];

  @override
  Future<void> play(String url, {double volume = 1}) async => played.add(url);

  @override
  Future<void> dispose() async {}
}
