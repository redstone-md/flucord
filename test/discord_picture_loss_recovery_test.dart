import 'package:fake_async/fake_async.dart';
import 'package:flucord/src/data/discord/discord_picture_loss_recovery.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a watched session recovers a lost packet', () {
    test('a hole is asked for at once, and again each round trip', () {
      fakeAsync((async) {
        final harness = _Harness(async);

        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        async.elapse(Duration.zero);
        expect(harness.video, [1]);
        // Asked the moment the packet past it landed, not on a timer.
        expect(harness.nacks, [
          [2],
        ]);

        // Repeated at the floor interval while nothing is measured.
        async.elapse(const Duration(milliseconds: 45));
        expect(harness.nacks, hasLength(2));

        // The retransmission lands inside the window: the stream is whole,
        // nothing was skipped, and the asking stops.
        harness.recovery.accept(_retransmission(2));
        async.elapse(Duration.zero);
        expect(harness.video, [1, 2, 3]);
        async.elapse(const Duration(milliseconds: 200));
        expect(harness.nacks, hasLength(2));
        expect(harness.keyframeAsks, isEmpty);
        harness.close();
      });
    });

    test('a keyframe is asked for only after the window closed', () {
      fakeAsync((async) {
        final harness = _Harness(async);

        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        async.elapse(Duration.zero);
        // The picture failed to open and the receiver asks for a keyframe
        // while the retransmission is still expected: held, not sent.
        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        expect(harness.keyframeAsks, isEmpty);
        async.elapse(const Duration(milliseconds: 60));
        expect(harness.keyframeAsks, isEmpty);
        expect(harness.video, [1]);

        // Past the window without an answer: the hole is given up, what
        // waited behind it is released, and the held ask goes out, once.
        async.elapse(const Duration(milliseconds: 100));
        expect(harness.video, [1, 3]);
        expect(harness.keyframeAsks, hasLength(1));
        // The retransmission arriving now is too late to be used, and does
        // not put a stale packet into the picture stream.
        harness.recovery.accept(_retransmission(2));
        async.elapse(Duration.zero);
        expect(harness.video, [1, 3]);
        // No more asks are repeated for a hole that was given up.
        final asked = harness.nacks.length;
        async.elapse(const Duration(milliseconds: 200));
        expect(harness.nacks, hasLength(asked));
        harness.close();
      });
    });

    test('a held keyframe ask outlives the rate limit', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        harness.recovery.accept(_video(1));
        async.elapse(Duration.zero);
        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        expect(harness.keyframeAsks, hasLength(1));

        // A hole opens and closes within the second: the ask is held by the
        // hole, then refused by the limit, and still owed.
        harness.recovery.accept(_video(3));
        async.elapse(Duration.zero);
        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        harness.recovery.accept(_retransmission(2));
        async.elapse(const Duration(milliseconds: 500));
        expect(harness.video, [1, 2, 3]);
        expect(harness.keyframeAsks, hasLength(1));

        // Paid on the first packet after the second is up.
        async.elapse(const Duration(milliseconds: 600));
        harness.recovery.accept(_video(4));
        async.elapse(Duration.zero);
        expect(harness.keyframeAsks, hasLength(2));
        harness.close();
      });
    });

    test('keyframe asks are rate limited to one a second', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        harness.recovery.accept(_video(1));

        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        async.elapse(const Duration(milliseconds: 500));
        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        expect(harness.keyframeAsks, hasLength(1));
        async.elapse(const Duration(milliseconds: 600));
        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        // The full intra request's command sequence tells the two apart.
        expect(harness.keyframeAsks.map((ask) => ask.commandSequence), [1, 2]);
        harness.close();
      });
    });

    test('the window follows the measured round trip', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        // A 150 ms round trip: the window becomes 300 ms.
        harness.roundTrip = const Duration(milliseconds: 150);

        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        async.elapse(const Duration(milliseconds: 200));
        // Inside a window a fixed 100 ms would have closed already.
        expect(harness.video, [1]);
        // And the ask is repeated per round trip, not per 40 ms.
        expect(harness.nacks.length, inInclusiveRange(2, 3));
        harness.recovery.accept(_retransmission(2));
        async.elapse(Duration.zero);
        expect(harness.video, [1, 2, 3]);
        harness.close();
      });
    });

    test('a retransmission restores its original, a late one is dropped', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        harness.recovery.accept(_retransmission(2));
        // Restored into its original's place, on the original's SSRC.
        harness.recovery.accept(_retransmission(2));
        async.elapse(Duration.zero);
        expect(harness.video, [1, 2, 3]);
        expect(harness.recovery.report(), [
          'video $_videoSsrc: 4 packets, 1 holes, retransmissions 1 used 1 '
              'late, 0 given up, keyframe asks 0 sent 0 held',
        ]);
        harness.close();
      });
    });

    test('the retransmission stream never opens a picture stream', () {
      fakeAsync((async) {
        final harness = _Harness(async);

        // Packets on the retransmission SSRC that are not retransmissions:
        // whatever they are, they carry no picture, and asking the server
        // to resend that stream's own sequence numbers gets nothing back.
        harness.recovery.accept(_onRtxSsrc(1));
        harness.recovery.accept(_onRtxSsrc(4));
        async.elapse(const Duration(milliseconds: 100));
        expect(harness.video, isEmpty);
        expect(harness.nacks, isEmpty);

        // While the real stream still recovers as usual.
        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        async.elapse(Duration.zero);
        expect(harness.nacks, [
          [2],
        ]);
        harness.close();
      });
    });

    test('two subscribers see each packet once, restored once', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        final second = <int>[];
        harness.recovery.orderedPackets.listen(
          (packet) => second.add(packet.$2.header.sequence),
        );
        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        harness.recovery.accept(_retransmission(2));
        async.elapse(Duration.zero);
        expect(harness.video, [1, 2, 3]);
        expect(second, [1, 2, 3]);
        // One pipeline: one hole, one ask, however many are listening.
        expect(harness.nacks, [
          [2],
        ]);
        harness.close();
      });
    });

    test('a packet on an SSRC nobody announced is dropped', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        harness.recovery.accept(_video(1, ssrc: 500));
        harness.recovery.accept(_video(3, ssrc: 500));
        async.elapse(const Duration(milliseconds: 200));
        expect(harness.video, isEmpty);
        expect(harness.nacks, isEmpty);
        expect(harness.recovery.report(), isEmpty);
        harness.close();
      });
    });

    test('reset clears every buffer and stops the tick', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        async.elapse(Duration.zero);
        harness.recovery.reset();
        expect(async.periodicTimerCount, 0);

        // Neither the hole nor what waited behind it survives.
        async.elapse(const Duration(seconds: 1));
        expect(harness.video, [1]);
        expect(harness.nacks, hasLength(1));
        expect(harness.recovery.report(), isEmpty);
        harness.close();
      });
    });

    test('the report line names what happened since the last one', () {
      fakeAsync((async) {
        final harness = _Harness(async);
        harness.recovery.accept(_video(1));
        harness.recovery.accept(_video(3));
        harness.recovery.requestKeyframe(mediaSsrc: _videoSsrc);
        async.elapse(const Duration(milliseconds: 200));
        expect(harness.recovery.report(), [
          'video $_videoSsrc: 2 packets, 1 holes, retransmissions 0 used 0 '
              'late, 1 given up, keyframe asks 1 sent 1 held',
        ]);
        // Counts start over; a quiet sender has no line.
        expect(harness.recovery.report(), isEmpty);
        harness.close();
      });
    });
  });
}

const _videoSsrc = 92;

DiscordRtpFrame _video(int sequence, {int ssrc = _videoSsrc}) =>
    DiscordRtpFrame(
      header: DiscordRtpHeader(
        sequence: sequence,
        timestamp: sequence * 3000,
        ssrc: ssrc,
        payloadType: DiscordRtpHeader.discordVideoPayloadType,
        marker: true,
      ),
      payload: [sequence],
    );

/// [sequence]'s retransmission (RFC 4588): on the SSRC above, with the
/// original sequence number ahead of the original payload.
DiscordRtpFrame _retransmission(int sequence) => DiscordRtpFrame(
  header: DiscordRtpHeader(
    sequence: 700 + sequence,
    timestamp: sequence * 3000,
    ssrc: _videoSsrc + 1,
    payloadType: DiscordRtpHeader.discordVideoRtxPayloadType,
    marker: true,
  ),
  payload: [sequence >> 8, sequence & 0xff, sequence],
);

/// A packet on the retransmission SSRC that is not a retransmission.
DiscordRtpFrame _onRtxSsrc(int sequence) => DiscordRtpFrame(
  header: DiscordRtpHeader(
    sequence: sequence,
    timestamp: sequence * 3000,
    ssrc: _videoSsrc + 1,
    payloadType: DiscordRtpHeader.discordVideoPayloadType,
  ),
  payload: [0, 0, 0],
);

/// The recovery on a fake clock, with one announced sender.
final class _Harness {
  _Harness(this.async) {
    recovery = DiscordPictureLossRecovery(
      senderFor: (ssrc) => ssrc == _videoSsrc ? 'remote-2' : null,
      roundTrip: () => roundTrip,
      now: () => async.elapsed,
    );
    recovery.orderedPackets.listen((packet) {
      expect(packet.$1, 'remote-2');
      video.add(packet.$2.header.sequence);
    });
    recovery.feedback.listen(feedback.add);
  }

  final FakeAsync async;
  late final DiscordPictureLossRecovery recovery;
  Duration? roundTrip;

  /// The sequences delivered in order.
  final List<int> video = [];
  final List<DiscordFeedbackRequest> feedback = [];

  /// The sequences asked for, one list per NACK.
  List<List<int>> get nacks => [
    for (final request in feedback.whereType<DiscordNackRequest>())
      request.sequences,
  ];

  List<DiscordKeyframeRequest> get keyframeAsks =>
      feedback.whereType<DiscordKeyframeRequest>().toList();

  void close() {
    recovery.dispose();
    async.elapse(Duration.zero);
  }
}
