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

  group('the refill after running dry', _primerTests);
}

void _primerTests() {
  const frame = Duration(milliseconds: 20);

  test('a new source is held until it has enough sound to absorb jitter', () {
    final primer = PlaybackPrimer(need: const Duration(milliseconds: 100));

    // Nothing consumed yet: held through the first four frames, let go on
    // the fifth, which makes 100 ms.
    for (var i = 0; i < 4; i++) {
      expect(primer.feed(frame, Duration.zero), isTrue, reason: 'frame $i');
    }
    expect(primer.feed(frame, Duration.zero), isFalse);
  });

  test('a source playing with slack is left alone', () {
    final primer = PlaybackPrimer(need: const Duration(milliseconds: 100));
    for (var i = 0; i < 5; i++) {
      primer.feed(frame, Duration.zero);
    }

    // Fed 100 ms ahead of what is consumed, frame after frame.
    var consumed = Duration.zero;
    for (var i = 0; i < 50; i++) {
      expect(primer.feed(frame, consumed), isFalse, reason: 'frame $i');
      consumed += frame;
    }
  });

  test('a source that ran dry is held again until it refills', () {
    final primer = PlaybackPrimer(need: const Duration(milliseconds: 100));
    for (var i = 0; i < 5; i++) {
      primer.feed(frame, Duration.zero);
    }

    // The speaker stopped, everything fed was played, and the next phrase
    // begins: held for four frames, let go on the fifth.
    const fed = Duration(milliseconds: 100);
    for (var i = 0; i < 4; i++) {
      expect(primer.feed(frame, fed), isTrue, reason: 'frame $i');
    }
    expect(primer.feed(frame, fed), isFalse);
  });
}
