import 'package:flucord/src/data/soloud_voice_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('turning playback off before it opened is not a failure', () async {
    final service = SoLoudVoicePlaybackService();

    // The room disables playback on every bind to the signalling service,
    // which happens long before an output device has been opened. Throwing
    // there surfaced "voice playback is not initialized" over a call that had
    // nothing wrong with it.
    await expectLater(service.setEnabled(false), completes);
  });

  test('turning it on without a device still says so', () async {
    final service = SoLoudVoicePlaybackService();

    // Asking for sound from a service that has no device is a real mistake,
    // and one the caller can act on.
    await expectLater(service.setEnabled(true), throwsStateError);
  });
}
