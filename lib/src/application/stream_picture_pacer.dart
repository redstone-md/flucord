import 'dart:async';
import 'dart:typed_data';

/// Hands access units to a decoder on the stream's own schedule.
///
/// Pictures arrive whenever the network delivers them: bunched after a burst,
/// spread thin on a quiet scene. Decoding each the instant it lands makes the
/// picture stutter, because the pipeline has no notion of when a frame is due.
/// Discord's own client plans every frame for a render time of its RTP
/// timestamp plus a playout delay (`postponeDecodeLevel`), and this does the
/// same in a small way: the first picture decodes at once, and after that the
/// delay grows towards [maxDelay], spacing decodes by the gap the sender
/// stamped into the RTP timestamps.
///
/// A frame whose slot has already passed is decoded immediately and the
/// schedule is re-anchored there, so a stall (a window coming back, a network
/// burst) is caught up rather than replayed slower than real time.
final class StreamPicturePacer {
  StreamPicturePacer({
    required void Function(Uint8List unit, int rtpTimestamp) submit,
    Duration Function()? now,
    this.maxDelay = const Duration(milliseconds: 100),
    this.delayStep = const Duration(milliseconds: 8),
    this.maxQueue = 48,
    this.onOverflow,
  }) : _submit = submit,
       _now = now ?? _monotonicNow;

  /// Asked when the queue had to be dropped: a buffer this deep means whole
  /// pictures were lost with it, and the decoder will produce nothing usable
  /// until a fresh keyframe arrives.
  final void Function()? onOverflow;

  /// Decodes one access unit, with the RTP timestamp that scheduled it (90
  /// kHz ticks). Called from the pacer's own timing, so this is where a slow
  /// decode cost is paid: no more than the stream's real pace.
  final void Function(Uint8List unit, int rtpTimestamp) _submit;

  final Duration Function() _now;

  /// The buffer the picture gets to sit in before its slot comes due.
  final Duration maxDelay;

  /// How much [maxDelay] is earned per picture: from zero (the first frame
  /// paints at once) to full in a second or two of playback.
  final Duration delayStep;

  /// Pictures allowed to pile up before giving up on pacing and draining.
  /// Overflow means the decoder is slower than the stream, and queueing more
  /// only adds latency on top of it. Sized past the [maxDelay] buffer (six
  /// frames at 60 fps) with room for arrival bursts, so a jittery network
  /// does not trip it every other second.
  final int maxQueue;

  final List<_PacedPicture> _pending = [];
  Timer? _timer;
  int? _anchorRtp;
  Duration? _anchorWall;
  Duration _delay = Duration.zero;
  int? _lastRtp;
  bool _disposed = false;

  /// Schedules one whole picture for its slot.
  ///
  /// A zero timestamp carries no schedule and decodes at once: a caller that
  /// has no RTP timestamp says so with zero, since real streams start theirs
  /// at a random offset.
  void submit(Uint8List unit, int rtpTimestamp) {
    if (_disposed) return;
    if (rtpTimestamp == 0) {
      _decodeNow(unit, rtpTimestamp);
      return;
    }
    // A picture older than the last one seen is a late arrival, and its slot
    // has passed by definition: decode it in place rather than reordering it
    // in front of frames the decoder may already hold.
    final last = _lastRtp;
    if (last != null && _rtpDelta(rtpTimestamp, last) < 0) {
      _decodeNow(unit, rtpTimestamp);
      return;
    }
    if (_anchorRtp == null || _anchorWall == null) {
      _anchor(unit, rtpTimestamp, _now());
      return;
    }
    if (_pending.length >= maxQueue) {
      // The buffer is full: pacing has lost. Drop what is waiting rather than
      // decode thirty frames back to back on this very thread, which is a
      // freeze a viewer feels. The dropped pictures leave the decoder with
      // broken references, so the caller asks for a keyframe to start over.
      _pending.clear();
      _cancelTimer();
      _decodeNow(unit, rtpTimestamp);
      onOverflow?.call();
      return;
    }
    final target = _slotFor(rtpTimestamp);
    if (target <= _now()) {
      _decodeNow(unit, rtpTimestamp);
      return;
    }
    _lastRtp = rtpTimestamp;
    _pending.add(_PacedPicture(unit, rtpTimestamp));
    _growDelay();
    _timer ??= Timer(target - _now(), _onSlotDue);
  }

  /// Throws away the schedule: whatever is pending decodes now, and the next
  /// picture starts a fresh one. Used when a session changes decoders.
  void flush() {
    _cancelTimer();
    for (final picture in _pending) {
      _submit(picture.unit, picture.rtpTimestamp);
    }
    _pending.clear();
    _anchorRtp = null;
    _anchorWall = null;
    _delay = Duration.zero;
    _lastRtp = null;
  }

  void dispose() {
    _disposed = true;
    flush();
  }

  void _onSlotDue() {
    _timer = null;
    if (_disposed || _pending.isEmpty) return;
    final picture = _pending.removeAt(0);
    // Submitted without re-anchoring: the slot was computed against the
    // anchor that is still standing, and the playout delay was already paid
    // when the picture queued. Re-anchoring here would move the anchor to
    // the decode time and add the delay again, so every decoded frame pushed
    // the next one a full maxDelay further out and the drain crawled at a
    // fraction of the stream's pace.
    _lastRtp = picture.rtpTimestamp;
    _submit(picture.unit, picture.rtpTimestamp);
    if (_pending.isEmpty) return;
    final target = _slotFor(_pending.first.rtpTimestamp);
    final wait = target - _now();
    if (wait <= Duration.zero) {
      _onSlotDue();
      return;
    }
    _timer = Timer(wait, _onSlotDue);
  }

  Duration _slotFor(int rtpTimestamp) {
    final anchorRtp = _anchorRtp!;
    final anchorWall = _anchorWall!;
    // RTP clocks run at 90 kHz; the slot lives in wall-clock microseconds.
    return anchorWall +
        Duration(
          microseconds: _rtpDelta(rtpTimestamp, anchorRtp) * 1000000 ~/ 90000,
        ) +
        _delay;
  }

  void _decodeNow(Uint8List unit, int rtpTimestamp) {
    _anchor(unit, rtpTimestamp, _now());
  }

  /// Re-anchors the schedule at the picture just decoded, so the next one is
  /// measured from here: the gap the sender stamped, plus the buffer.
  void _anchor(Uint8List unit, int rtpTimestamp, Duration wall) {
    _cancelTimer();
    _anchorRtp = rtpTimestamp;
    _anchorWall = wall;
    _lastRtp = rtpTimestamp;
    _submit(unit, rtpTimestamp);
  }

  void _growDelay() {
    final grown = _delay + delayStep;
    _delay = grown > maxDelay ? maxDelay : grown;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// RTP timestamps are 32 bits and wrap; the delta only makes sense signed.
  static int _rtpDelta(int later, int earlier) {
    final delta = (later - earlier) & 0xFFFFFFFF;
    return delta >= 0x80000000 ? delta - 0x100000000 : delta;
  }

  static Duration _monotonicNow() {
    final stamp = DateTime.now();
    return Duration(
      microseconds:
          stamp.microsecondsSinceEpoch - _epoch.microsecondsSinceEpoch,
    );
  }

  static final DateTime _epoch = DateTime.now();
}

final class _PacedPicture {
  const _PacedPicture(this.unit, this.rtpTimestamp);

  final Uint8List unit;
  final int rtpTimestamp;
}
