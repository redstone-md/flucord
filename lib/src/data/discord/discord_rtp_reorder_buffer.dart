import 'discord_rtp_packet.dart';

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

  List<DiscordRtpFrame> add(DiscordRtpFrame frame) {
    _nextSequence ??= frame.header.sequence;
    final distance = _forwardDistance(_nextSequence!, frame.header.sequence);
    if (distance >= _halfSequenceRange ||
        _pending.containsKey(frame.header.sequence)) {
      return const [];
    }

    _pending[frame.header.sequence] = frame;
    if (distance >= maxReorderDistance) _skipMissingFrames();
    return _drainContiguousFrames();
  }

  void reset() {
    _pending.clear();
    _nextSequence = null;
  }

  void _skipMissingFrames() {
    final expected = _nextSequence!;
    _nextSequence = _pending.keys.reduce((nearest, candidate) {
      final nearestDistance = _forwardDistance(expected, nearest);
      final candidateDistance = _forwardDistance(expected, candidate);
      return candidateDistance < nearestDistance ? candidate : nearest;
    });
  }

  List<DiscordRtpFrame> _drainContiguousFrames() {
    final ready = <DiscordRtpFrame>[];
    while (true) {
      final frame = _pending.remove(_nextSequence);
      if (frame == null) break;
      ready.add(frame);
      _nextSequence = (_nextSequence! + 1) & _sequenceMask;
    }
    return ready;
  }

  static int _forwardDistance(int from, int to) => (to - from) & _sequenceMask;
}
