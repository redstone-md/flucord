import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_rtp_reorder_buffer.dart';

void main() {
  _timeWindowCases();

  test('reorders delayed RTP frames and drops duplicate replays', () {
    final buffer = DiscordRtpReorderBuffer();

    expect(_sequences(buffer.add(_frame(10))), [10]);
    expect(buffer.add(_frame(12)), isEmpty);
    expect(buffer.add(_frame(12)), isEmpty);
    expect(_sequences(buffer.add(_frame(11))), [11, 12]);
    expect(buffer.add(_frame(10)), isEmpty);
    expect(buffer.pendingCount, 0);
  });

  test('orders packets across the 16-bit sequence wrap', () {
    final buffer = DiscordRtpReorderBuffer();

    expect(_sequences(buffer.add(_frame(0xffff))), [0xffff]);
    expect(buffer.add(_frame(1)), isEmpty);
    expect(_sequences(buffer.add(_frame(0))), [0, 1]);
  });

  test('skips a missing packet when the reorder window is exhausted', () {
    final buffer = DiscordRtpReorderBuffer(maxReorderDistance: 3);

    expect(_sequences(buffer.add(_frame(10))), [10]);
    expect(buffer.add(_frame(12)), isEmpty);
    expect(buffer.add(_frame(13)), isEmpty);
    final recovered = buffer.add(_frame(14));
    expect(_sequences(recovered), [12, 13, 14]);
    expect(recovered.map((frame) => frame.missingFramesBefore), [1, 0, 0]);
    expect(buffer.add(_frame(11)), isEmpty);
  });

  test('validates the configured reorder distance', () {
    expect(
      () => DiscordRtpReorderBuffer(maxReorderDistance: 0),
      throwsRangeError,
    );
    expect(
      () => DiscordRtpReorderBuffer(maxReorderDistance: 0x8000),
      throwsRangeError,
    );
  });
}

List<int> _sequences(List<DiscordOrderedRtpFrame> frames) => frames
    .map((ordered) => ordered.frame.header.sequence)
    .toList(growable: false);

DiscordRtpFrame _frame(int sequence) => DiscordRtpFrame(
  header: DiscordRtpHeader(sequence: sequence, timestamp: sequence, ssrc: 7),
  payload: [sequence & 0xff],
);

/// The time-based window: what video uses, so a hole waits for a
/// retransmission by the clock rather than by how many packets pass it.
void _timeWindowCases() {
  test('a hole is held open for the window, however many packets pass it', () {
    var now = Duration.zero;
    final buffer = DiscordRtpReorderBuffer(
      holdTime: () => const Duration(milliseconds: 100),
      now: () => now,
    );

    expect(_sequences(buffer.add(_frame(10))), [10]);
    // Twenty packets past the hole: a count-based window would have given
    // up long ago.
    for (var sequence = 12; sequence < 32; sequence++) {
      expect(buffer.add(_frame(sequence)), isEmpty);
    }
    expect(buffer.missingSequences, [11]);
    now = const Duration(milliseconds: 99);
    expect(buffer.releaseExpired(), isEmpty);

    // The retransmission lands inside the window and everything drains
    // whole, with nothing reported missing.
    final drained = buffer.add(_frame(11));
    expect(_sequences(drained), List.generate(21, (index) => 11 + index));
    expect(drained.first.missingFramesBefore, 0);
    expect(buffer.missingSequences, isEmpty);
  });

  test('a hole older than the window is given up without a new packet', () {
    var now = Duration.zero;
    final buffer = DiscordRtpReorderBuffer(
      holdTime: () => const Duration(milliseconds: 100),
      now: () => now,
    );
    buffer.add(_frame(10));
    buffer.add(_frame(12));
    now = const Duration(milliseconds: 50);
    buffer.add(_frame(14));
    expect(buffer.missingSequences, [11, 13]);

    // The first hole was exposed at zero, the second at 50 ms: each waits
    // its own window, measured from when a packet first passed it.
    now = const Duration(milliseconds: 100);
    final first = buffer.releaseExpired();
    expect(_sequences(first), [12]);
    expect(first.single.missingFramesBefore, 1);
    expect(buffer.missingSequences, [13]);

    now = const Duration(milliseconds: 150);
    final second = buffer.releaseExpired();
    expect(_sequences(second), [14]);
    expect(second.single.missingFramesBefore, 1);
    expect(buffer.missingSequences, isEmpty);

    // What arrives after the window closed is too late to be used.
    expect(buffer.wants(11), isFalse);
    expect(buffer.add(_frame(11)), isEmpty);
    expect(buffer.wants(16), isTrue);
  });

  test('the window follows the clock it is given', () {
    var now = Duration.zero;
    var window = const Duration(milliseconds: 100);
    final buffer = DiscordRtpReorderBuffer(
      holdTime: () => window,
      now: () => now,
    );
    buffer.add(_frame(1));
    buffer.add(_frame(3));
    // A longer round trip widens the window while the hole is still open.
    window = const Duration(milliseconds: 300);
    now = const Duration(milliseconds: 200);
    expect(buffer.releaseExpired(), isEmpty);
    now = const Duration(milliseconds: 300);
    expect(_sequences(buffer.releaseExpired()), [3]);
  });
}
