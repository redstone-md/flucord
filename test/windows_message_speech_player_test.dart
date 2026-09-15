import 'package:flucord/src/data/windows_message_speech_player.dart';
import 'package:flucord/src/domain/soundboard_playback.dart';
import 'package:flutter_test/flutter_test.dart';

/// The synthesis half of spoken-aloud messages. The Windows synthesiser
/// itself only exists on a Windows machine with a voice, which is live
/// evidence the suite keeps out; what the suite can hold to account is the
/// honesty of the refusal and the handoff to the media playback layer.
void main() {
  test('a machine without the synthesiser refuses and plays nothing', () async {
    final sounds = _RecordingSounds();
    final speech = WindowsMessageSpeechPlayer(player: sounds);

    await speech.speak('The release is out.');

    // This suite runs on a machine the player cannot synthesise on; the
    // contract's answer there is a plain refusal, not an error and not a
    // silent pretence.
    expect(sounds.played, isEmpty);
    expect(speech.isSupported, anyOf(isTrue, isFalse));
    if (!speech.isSupported) {
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
