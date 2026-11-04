import 'package:flucord/src/data/discord/voice_reconnect_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Duration?> drain(VoiceReconnectBackoff backoff, int count) => [
    for (var i = 0; i < count; i++) backoff.next(),
  ];

  test('each wait doubles from two seconds', () {
    final backoff = VoiceReconnectBackoff(jitter: () => 0);

    expect(drain(backoff, 4), const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
    ]);
  });

  test('the wait stops growing at the cap', () {
    final backoff = VoiceReconnectBackoff(
      maxDelay: const Duration(seconds: 5),
      jitter: () => 0,
    );

    expect(drain(backoff, 4), const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 5),
      Duration(seconds: 5),
    ]);
  });

  test('jitter takes up to a quarter off a wait, never adds to it', () {
    final backoff = VoiceReconnectBackoff(jitter: () => 0.5);

    expect(drain(backoff, 2), const [
      Duration(milliseconds: 1750),
      Duration(milliseconds: 3500),
    ]);
  });

  test('gives up once every attempt is spent', () {
    final backoff = VoiceReconnectBackoff(maxAttempts: 3, jitter: () => 0);

    expect(drain(backoff, 4), const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      null,
    ]);
  });

  test('a reset starts again from the first wait, with every attempt', () {
    final backoff = VoiceReconnectBackoff(maxAttempts: 2, jitter: () => 0)
      ..next()
      ..next()
      ..reset();

    expect(drain(backoff, 3), const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      null,
    ]);
  });
}
