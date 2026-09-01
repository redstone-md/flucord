import '../../monotonic_clock.dart';
import 'discord_rtp_packet.dart';

final class DiscordOrderedRtpFrame {
  const DiscordOrderedRtpFrame({
    required this.frame,
    this.missingFramesBefore = 0,
  });

  final DiscordRtpFrame frame;
  final int missingFramesBefore;
}

/// Puts RTP frames back into sequence order.
///
/// Two ways to decide when a hole is a loss. Audio counts: a hole is given up
/// once [maxReorderDistance] packets have landed past it, which is cheap and
/// right for a stream where a late packet is worth nothing anyway. Video
/// waits by the clock: a hole stays open for [holdTime] measured from the
/// moment a packet first passed it, whatever arrives meanwhile, so a
/// retransmission asked for at once has a round trip or two to land before
/// the picture it belongs to is closed without it. The window is a callback
/// because it follows the measured round trip and changes while a hole is
/// open.
final class DiscordRtpReorderBuffer {
  DiscordRtpReorderBuffer({
    this.maxReorderDistance = 3,
    Duration Function()? holdTime,
    Duration Function()? now,
  }) : _holdTime = holdTime,
       _now = now ?? monotonicNow {
    if (maxReorderDistance < 1 || maxReorderDistance >= _halfSequenceRange) {
      throw RangeError.range(
        maxReorderDistance,
        1,
        _halfSequenceRange - 1,
        'maxReorderDistance',
      );
    }
  }

  static const int _sequenceMask = 0xffff;
  static const int _halfSequenceRange = 0x8000;

  final int maxReorderDistance;
  final Duration Function()? _holdTime;
  final Duration Function() _now;
  final Map<int, _HeldFrame> _pending = {};
  int? _nextSequence;

  int get pendingCount => _pending.length;

  /// The sequence the buffer is waiting for, or null before the first packet.
  int? get nextSequence => _nextSequence;

  /// Whether anything is held behind a hole.
  bool get hasHoles => _pending.isNotEmpty;

  /// Every sequence between the one waited for and the furthest one held
  /// that has not arrived: what a retransmission ask should name.
  List<int> get missingSequences {
    final expected = _nextSequence;
    if (expected == null || _pending.isEmpty) return const [];
    var span = 0;
    for (final sequence in _pending.keys) {
      final distance = _forwardDistance(expected, sequence);
      if (distance > span) span = distance;
    }
    return [
      for (var distance = 0; distance < span; distance++)
        if (!_pending.containsKey((expected + distance) & _sequenceMask))
          (expected + distance) & _sequenceMask,
    ];
  }

  /// Whether [sequence] would still be used if it arrived now: not yet
  /// passed, and not already held.
  bool wants(int sequence) {
    final expected = _nextSequence;
    if (expected == null) return true;
    return _forwardDistance(expected, sequence) < _halfSequenceRange &&
        !_pending.containsKey(sequence);
  }

  List<DiscordOrderedRtpFrame> add(DiscordRtpFrame frame) {
    _nextSequence ??= frame.header.sequence;
    final distance = _forwardDistance(_nextSequence!, frame.header.sequence);
    if (distance >= _halfSequenceRange ||
        _pending.containsKey(frame.header.sequence)) {
      return const [];
    }

    _pending[frame.header.sequence] = _HeldFrame(frame, _now());
    if (_holdTime == null) {
      final missingFrames = distance >= maxReorderDistance
          ? _skipMissingFrames()
          : 0;
      return _drainContiguousFrames(missingFrames);
    }
    return _releaseByTime();
  }

  /// Gives up on every hole older than the window, and hands out what was
  /// waiting behind it. Only the time-based buffer has anything to release:
  /// a count-based one only moves when a packet lands.
  List<DiscordOrderedRtpFrame> releaseExpired() =>
      _holdTime == null ? const [] : _releaseByTime();

  void reset() {
    _pending.clear();
    _nextSequence = null;
  }

  List<DiscordOrderedRtpFrame> _releaseByTime() {
    final ready = <DiscordOrderedRtpFrame>[];
    final now = _now();
    final holdTime = _holdTime!();
    var missing = 0;
    while (true) {
      ready.addAll(_drainContiguousFrames(missing));
      // Whatever is still held sits behind a hole. The hole opened when the
      // first packet passed it, which is the oldest arrival held.
      if (_pending.isEmpty || now - _oldestArrival() < holdTime) break;
      missing = _skipMissingFrames();
    }
    return ready;
  }

  Duration _oldestArrival() => _pending.values
      .map((held) => held.arrivedAt)
      .reduce((a, b) => a < b ? a : b);

  int _skipMissingFrames() {
    final expected = _nextSequence!;
    final nearest = _pending.keys.reduce((nearest, candidate) {
      final nearestDistance = _forwardDistance(expected, nearest);
      final candidateDistance = _forwardDistance(expected, candidate);
      return candidateDistance < nearestDistance ? candidate : nearest;
    });
    _nextSequence = nearest;
    return _forwardDistance(expected, nearest);
  }

  List<DiscordOrderedRtpFrame> _drainContiguousFrames(int missingFrames) {
    final ready = <DiscordOrderedRtpFrame>[];
    while (true) {
      final held = _pending.remove(_nextSequence);
      if (held == null) break;
      ready.add(
        DiscordOrderedRtpFrame(
          frame: held.frame,
          missingFramesBefore: ready.isEmpty ? missingFrames : 0,
        ),
      );
      _nextSequence = (_nextSequence! + 1) & _sequenceMask;
    }
    return ready;
  }

  static int _forwardDistance(int from, int to) => (to - from) & _sequenceMask;
}

final class _HeldFrame {
  const _HeldFrame(this.frame, this.arrivedAt);

  final DiscordRtpFrame frame;
  final Duration arrivedAt;
}
