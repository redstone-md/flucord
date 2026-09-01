import 'discord_rtp_packet.dart';

final class DiscordOrderedRtpFrame {
  const DiscordOrderedRtpFrame({
    required this.frame,
    this.missingFramesBefore = 0,
  });

  final DiscordRtpFrame frame;
  final int missingFramesBefore;
}

final class DiscordRtpReorderBuffer {
  DiscordRtpReorderBuffer({this.maxReorderDistance = 3}) {
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
  final Map<int, DiscordRtpFrame> _pending = {};
  int? _nextSequence;

  int get pendingCount => _pending.length;

  /// The sequence the buffer is waiting for, or null before the first packet.
  ///
  /// A caller that wants to retransmit lost packets needs this: the hole is
  /// visible the moment a packet arrives ahead of it, while everything the
  /// buffer could still accept is what it has not passed yet.
  int? get nextSequence => _nextSequence;

  List<DiscordOrderedRtpFrame> add(DiscordRtpFrame frame) {
    _nextSequence ??= frame.header.sequence;
    final distance = _forwardDistance(_nextSequence!, frame.header.sequence);
    if (distance >= _halfSequenceRange ||
        _pending.containsKey(frame.header.sequence)) {
      return const [];
    }

    _pending[frame.header.sequence] = frame;
    final missingFrames = distance >= maxReorderDistance
        ? _skipMissingFrames()
        : 0;
    return _drainContiguousFrames(missingFrames);
  }

  void reset() {
    _pending.clear();
    _nextSequence = null;
  }

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
      final frame = _pending.remove(_nextSequence);
      if (frame == null) break;
      ready.add(
        DiscordOrderedRtpFrame(
          frame: frame,
          missingFramesBefore: ready.isEmpty ? missingFrames : 0,
        ),
      );
      _nextSequence = (_nextSequence! + 1) & _sequenceMask;
    }
    return ready;
  }

  static int _forwardDistance(int from, int to) => (to - from) & _sequenceMask;
}
