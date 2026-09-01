import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flucord/src/application/stream_picture_pacer.dart';
import 'package:flutter_test/flutter_test.dart';

/// One 30 fps frame's worth of RTP ticks at 90 kHz.
const _frameTicks = 3000;

Uint8List _unit(int fill) => Uint8List.fromList(List.filled(fill, 1));

void main() {
  test('the first picture decodes at once, whatever its timestamp', () {
    fakeAsync((async) {
      final decoded = <int>[];
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
      );
      pacer.submit(_unit(4), 90000);
      expect(decoded, [4]);
      pacer.dispose();
    });
  });

  test('a caller without a timestamp never gets paced', () {
    fakeAsync((async) {
      final decoded = <int>[];
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
      );
      for (var index = 0; index < 10; index++) {
        pacer.submit(_unit(index), 0);
      }
      expect(decoded, hasLength(10));
      async.elapse(const Duration(seconds: 1));
      expect(decoded, hasLength(10));
      pacer.dispose();
    });
  });

  test('frames come out spaced by the gap their timestamps carry', () {
    fakeAsync((async) {
      final decoded = <int>[];
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
      );
      // The first frame anchors; the two after it wait for their slots.
      pacer.submit(_unit(1), 0);
      pacer.submit(_unit(2), _frameTicks);
      pacer.submit(_unit(3), 2 * _frameTicks);
      expect(decoded, hasLength(1));
      // The buffer is still filling, so slots sit a little past one frame
      // gap; what matters is the order and that nothing outruns its stamp.
      async.elapse(const Duration(milliseconds: 500));
      expect(decoded, [1, 2, 3]);
      pacer.dispose();
    });
  });

  test('a frame whose slot has passed decodes now and re-anchors', () {
    fakeAsync((async) {
      final decoded = <int>[];
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
      );
      pacer.submit(_unit(1), 0);
      pacer.submit(_unit(2), _frameTicks);
      // The second frame's slot came and went before the pacer got to it.
      async.elapse(const Duration(milliseconds: 500));
      final afterStall = decoded.length;
      pacer.submit(_unit(3), 2 * _frameTicks);
      // Late: decoded immediately, not queued behind the stall.
      expect(decoded.length, afterStall + 1);
      // And the next frame is measured from here, not from the stale anchor.
      pacer.submit(_unit(4), 3 * _frameTicks);
      async.elapse(const Duration(milliseconds: 25));
      expect(decoded.length, afterStall + 1);
      async.elapse(const Duration(milliseconds: 25));
      expect(decoded.length, afterStall + 2);
      pacer.dispose();
    });
  });

  test('a picture older than the last one seen is not queued ahead of it', () {
    fakeAsync((async) {
      final decoded = <int>[];
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
      );
      pacer.submit(_unit(1), 0);
      pacer.submit(_unit(2), 5 * _frameTicks);
      pacer.submit(_unit(3), 2 * _frameTicks);
      // The late arrival is decoded in place, whatever the queue holds.
      expect(decoded, [1, 3]);
      pacer.dispose();
    });
  });

  test('a picture whose slot is far ahead decodes now and re-anchors', () {
    fakeAsync((async) {
      final decoded = <int>[];
      var overflowAsked = 0;
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
        onOverflow: () => overflowAsked++,
      );
      pacer.submit(_unit(1), 0);
      pacer.submit(_unit(2), _frameTicks);
      // The sender's clock jumped a second ahead of ours. Queueing this for
      // a slot a second out, and everything after it behind that, is what
      // filled the queue and looped the overflow.
      pacer.submit(_unit(3), 90000);
      expect(decoded, [1, 2, 3]);
      // Measured from here: the next picture waits one frame, not a second.
      pacer.submit(_unit(4), 90000 + _frameTicks);
      expect(decoded, hasLength(3));
      async.elapse(const Duration(milliseconds: 60));
      expect(decoded, [1, 2, 3, 4]);
      expect(overflowAsked, 0);
      pacer.dispose();
    });
  });

  test('an overflow keeps the newest keyframe and what follows it', () {
    fakeAsync((async) {
      final decoded = <int>[];
      var overflowAsked = 0;
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
        maxQueue: 5,
        maxDelay: const Duration(seconds: 1),
        isKeyframe: (unit) => unit.length == 3,
        onOverflow: () => overflowAsked++,
      );
      pacer.submit(_unit(10), 0);
      for (var index = 1; index <= 5; index++) {
        pacer.submit(_unit(index), index * _frameTicks);
      }
      pacer.submit(_unit(6), 6 * _frameTicks);
      // Everything before the keyframe went; the keyframe decodes now and
      // the rest follow it at their pace. The decoder's references are whole,
      // so nobody has to ask the sender for anything.
      expect(decoded, [10, 3]);
      expect(overflowAsked, 0);
      async.elapse(const Duration(seconds: 1));
      expect(decoded, [10, 3, 4, 5, 6]);
      pacer.dispose();
    });
  });

  test('an overflow met by a keyframe in hand asks for nothing', () {
    fakeAsync((async) {
      final decoded = <int>[];
      var overflowAsked = 0;
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
        maxQueue: 3,
        maxDelay: const Duration(seconds: 1),
        isKeyframe: (unit) => unit.length == 9,
        onOverflow: () => overflowAsked++,
      );
      pacer.submit(_unit(1), 0);
      for (var index = 1; index <= 3; index++) {
        pacer.submit(_unit(2), index * _frameTicks);
      }
      // The queue held no keyframe, but the picture that overflowed it is
      // one: the references it leaves behind are whole.
      pacer.submit(_unit(9), 4 * _frameTicks);
      expect(decoded, [1, 9]);
      expect(overflowAsked, 0);
      pacer.dispose();
    });
  });

  test('a buffer that overflows drops the queue and asks for a keyframe', () {
    fakeAsync((async) {
      final decoded = <int>[];
      var overflowAsked = 0;
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
        maxQueue: 5,
        maxDelay: const Duration(seconds: 1),
        isKeyframe: (_) => false,
        onOverflow: () => overflowAsked++,
      );
      pacer.submit(_unit(0), 0);
      for (var index = 1; index <= 5; index++) {
        pacer.submit(_unit(index), index * _frameTicks);
      }
      pacer.submit(_unit(6), 6 * _frameTicks);
      // The queue went, only the newest frame decoded, and the keyframe ask
      // went out: decoding the dropped frames back to back would be a freeze.
      expect(decoded, [0, 6]);
      expect(overflowAsked, 1);
      pacer.dispose();
    });
  });

  test('a steady stream drains at its own pace without overflowing', () {
    fakeAsync((async) {
      final decoded = <int>[];
      var overflowAsked = 0;
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
        onOverflow: () => overflowAsked++,
      );
      // 90 frames at 60 fps, arriving in real time. The playout delay is a
      // one-time head start, not a tax per frame: the drain keeps the
      // stream's pace, the queue never nears its limit.
      const ticks60 = 1500;
      for (var index = 0; index < 90; index++) {
        pacer.submit(_unit(index), index * ticks60);
        async.elapse(const Duration(milliseconds: 16));
      }
      async.elapse(const Duration(milliseconds: 200));
      expect(overflowAsked, 0);
      expect(decoded, hasLength(90));
      pacer.dispose();
    });
  });

  test('flush decodes what is pending and forgets the schedule', () {
    fakeAsync((async) {
      final decoded = <int>[];
      final pacer = StreamPicturePacer(
        submit: (unit, _) => decoded.add(unit.length),
        now: () => async.elapsed,
      );
      pacer.submit(_unit(1), 0);
      pacer.submit(_unit(2), _frameTicks);
      pacer.flush();
      expect(decoded, hasLength(2));
      // After a flush the schedule restarts: the next picture is immediate.
      pacer.submit(_unit(3), 10 * _frameTicks);
      expect(decoded, hasLength(3));
      pacer.dispose();
    });
  });
}
