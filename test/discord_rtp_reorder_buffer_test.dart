import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_rtp_reorder_buffer.dart';

void main() {
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
    expect(_sequences(buffer.add(_frame(14))), [12, 13, 14]);
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

List<int> _sequences(List<DiscordRtpFrame> frames) =>
    frames.map((frame) => frame.header.sequence).toList(growable: false);

DiscordRtpFrame _frame(int sequence) => DiscordRtpFrame(
  header: DiscordRtpHeader(sequence: sequence, timestamp: sequence, ssrc: 7),
  payload: [sequence & 0xff],
);
