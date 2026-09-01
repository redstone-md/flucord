import 'dart:async';

import '../../monotonic_clock.dart';
import 'discord_rtp_packet.dart';
import 'discord_rtp_reorder_buffer.dart';

/// Feedback the recovery wants sent to the media server about one sender's
/// pictures. Typed, not bytes: whoever owns the cipher turns it into RTCP.
sealed class DiscordFeedbackRequest {
  const DiscordFeedbackRequest({required this.mediaSsrc});

  final int mediaSsrc;
}

/// Ask for these sequences again (RFC 4585 NACK).
final class DiscordNackRequest extends DiscordFeedbackRequest {
  const DiscordNackRequest({required super.mediaSsrc, required this.sequences});

  final List<int> sequences;
}

/// Ask the sender for a keyframe (RFC 4585 PLI and RFC 5104 FIR).
final class DiscordKeyframeRequest extends DiscordFeedbackRequest {
  const DiscordKeyframeRequest({
    required super.mediaSsrc,
    required this.commandSequence,
  });

  /// The full intra request's command sequence: one more per ask, never
  /// reset, so the sender can tell a repeat from a new one.
  final int commandSequence;
}

/// Recovers a lost video packet before a keyframe is asked for (ADR-0006).
///
/// Decrypted non-audio frames go in; frames in sequence order, paired with
/// their sender, and typed feedback requests come out. One instance per
/// gateway client: the reorder state and the asks belong to the connection.
///
/// A retransmission (RFC 4588) is put back in its original's place first.
/// After that a packet is owned or dropped. An SSRC nobody has claimed
/// belongs to a participant whose announcement has not arrived, or is the
/// retransmission SSRC carrying something that is not one. Neither opens a
/// reorder buffer: guessing the owner would draw one person's face over
/// another's tile, and a buffer on the retransmission stream asks the server
/// for sequence numbers that carry no picture.
final class DiscordPictureLossRecovery {
  DiscordPictureLossRecovery({
    required String? Function(int videoSsrc) senderFor,
    required Duration? Function() roundTrip,
    Duration Function()? now,
  }) : _senderFor = senderFor,
       _roundTrip = roundTrip,
       _now = now ?? monotonicNow;

  final String? Function(int videoSsrc) _senderFor;
  final Duration? Function() _roundTrip;

  /// The clock the recovery runs on.
  final Duration Function() _now;

  final StreamController<(String, DiscordRtpFrame)> _ordered =
      StreamController.broadcast();

  /// Synchronous so an ask leaves with the packet that exposed the hole.
  final StreamController<DiscordFeedbackRequest> _feedback = StreamController(
    sync: true,
  );

  final Map<int, _VideoReceive> _video = {};
  Timer? _recoveryTimer;
  int _fullIntraRequests = 0;

  /// How often open holes are looked at: the floor of the ask interval, and
  /// the granularity the retransmission window closes at.
  static const _recoveryTick = Duration(milliseconds: 40);

  /// How many sequences one ask names. A hole wider than this is a sender
  /// restart or a whole burst gone, not something a retransmission mends,
  /// and an ask sized to it would not fit a datagram.
  static const _maxNackedSequences = 128;

  /// Somebody else's pictures, put back in order and paired with whoever is
  /// sending them.
  Stream<(String, DiscordRtpFrame)> get orderedPackets => _ordered.stream;

  /// What to send the media server, in the order it is wanted.
  Stream<DiscordFeedbackRequest> get feedback => _feedback.stream;

  /// How long a hole waits for its retransmission: two round trips, so a
  /// NACK lost once still has time to be answered.
  Duration get _retransmitWindow {
    const floor = Duration(milliseconds: 100);
    const ceiling = Duration(milliseconds: 500);
    final roundTrip = _roundTrip();
    if (roundTrip == null) return floor;
    final window = roundTrip * 2;
    if (window < floor) return floor;
    return window > ceiling ? ceiling : window;
  }

  /// How often an unanswered ask is repeated: once a round trip, no faster
  /// than the recovery tick.
  Duration get _nackInterval {
    final roundTrip = _roundTrip();
    return roundTrip == null || roundTrip < _recoveryTick
        ? _recoveryTick
        : roundTrip;
  }

  /// Accepts one decrypted packet that is not audio.
  void accept(DiscordRtpFrame frame) {
    var retransmitted = false;
    if (frame.header.payloadType ==
        DiscordRtpHeader.discordVideoRtxPayloadType) {
      final restored = _restoreRetransmission(frame);
      if (restored == null) return;
      frame = restored;
      retransmitted = true;
    }
    final ssrc = frame.header.ssrc;
    if (_senderFor(ssrc) == null) return;
    final receive = _video.putIfAbsent(ssrc, () => _newVideoReceive(ssrc));
    receive.packets++;
    if (retransmitted) {
      if (!receive.buffer.wants(frame.header.sequence)) {
        receive.retransmissionsLate++;
        return;
      }
      receive.retransmissionsUsed++;
    }
    _release(receive, receive.buffer.add(frame));
    _askForHoles(receive);
  }

  /// Asks the sender for a keyframe, unless a retransmission is still
  /// expected on that stream: a hole inside its window may yet be filled,
  /// and the ask is paid when the last hole closes instead, either way it
  /// closes. Rate limited to one a second per stream, so a burst of loss
  /// does not become a burst of asks.
  void requestKeyframe({required int mediaSsrc}) {
    final receive = _video.putIfAbsent(
      mediaSsrc,
      () => _newVideoReceive(mediaSsrc),
    );
    if (receive.buffer.hasHoles) {
      receive.keyframeOwed = true;
      receive.keyframesHeld++;
      return;
    }
    _sendKeyframeAsk(receive);
  }

  /// Forgets every buffer and every ask: a new session starts clean.
  void reset() {
    _video.clear();
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  /// One line per sender that saw anything since the last report, and
  /// starts the counts over.
  List<String> report() {
    final lines = <String>[];
    for (final receive in _video.values) {
      if (receive.packets == 0 && receive.keyframeAsks == 0) continue;
      lines.add(
        'video ${receive.ssrc}: ${receive.packets} packets, '
        '${receive.holes} holes, retransmissions '
        '${receive.retransmissionsUsed} used ${receive.retransmissionsLate} '
        'late, ${receive.holesGivenUp} given up, keyframe asks '
        '${receive.keyframeAsks} sent ${receive.keyframesHeld} held',
      );
      receive.resetCounters();
    }
    return lines;
  }

  Future<void> dispose() async {
    reset();
    await _feedback.close();
    await _ordered.close();
  }

  _VideoReceive _newVideoReceive(int ssrc) => _VideoReceive(
    ssrc,
    DiscordRtpReorderBuffer(holdTime: () => _retransmitWindow, now: _now),
  );

  /// Puts a retransmission back in the original packet's place.
  ///
  /// Retransmissions ride the video SSRC one above their original's (RFC
  /// 4588), with the original sequence number ahead of the original payload.
  DiscordRtpFrame? _restoreRetransmission(DiscordRtpFrame frame) {
    final payload = frame.payload;
    if (payload.length <= 2) return null;
    return DiscordRtpFrame(
      header: DiscordRtpHeader(
        sequence: (payload[0] << 8) | payload[1],
        timestamp: frame.header.timestamp,
        ssrc: (frame.header.ssrc - 1) & 0xffffffff,
        payloadType: DiscordRtpHeader.discordVideoPayloadType,
        marker: frame.header.marker,
      ),
      payload: payload.sublist(2),
    );
  }

  /// Hands ordered packets on, and pays a keyframe ask that was held back
  /// once no hole is open any more. An ask the rate limit refuses stays
  /// owed, and is paid on a later packet.
  void _release(_VideoReceive receive, List<DiscordOrderedRtpFrame> ordered) {
    final userId = _senderFor(receive.ssrc);
    for (final entry in ordered) {
      receive.holesGivenUp += entry.missingFramesBefore;
      if (userId != null && !_ordered.isClosed) {
        _ordered.add((userId, entry.frame));
      }
    }
    if (receive.keyframeOwed &&
        !receive.buffer.hasHoles &&
        _sendKeyframeAsk(receive)) {
      receive.keyframeOwed = false;
    }
  }

  /// Asks for what is missing: at once for a hole a packet just exposed,
  /// then every hole again each round trip while any stays open. Stops by
  /// itself: a hole closes when its packet lands or when the window gives
  /// up on it.
  void _askForHoles(_VideoReceive receive) {
    final holes = receive.buffer.missingSequences;
    if (holes.isEmpty) {
      receive.asked.clear();
      return;
    }
    final now = _now();
    final fresh = holes.where((hole) => !receive.asked.contains(hole)).toList();
    receive.holes += fresh.length;
    if (now >= receive.nextAsk) {
      receive.nextAsk = now + _nackInterval;
      receive.asked
        ..clear()
        ..addAll(holes);
      _sendNack(receive.ssrc, holes);
    } else if (fresh.isNotEmpty) {
      receive.asked.addAll(fresh);
      _sendNack(receive.ssrc, fresh);
    }
    _recoveryTimer ??= Timer.periodic(_recoveryTick, (_) => _recover());
  }

  /// Runs while any hole is open: gives up on holes past their window, and
  /// repeats the asks that are due.
  void _recover() {
    var anyHoles = false;
    for (final receive in _video.values) {
      if (!receive.buffer.hasHoles) continue;
      _release(receive, receive.buffer.releaseExpired());
      _askForHoles(receive);
      anyHoles |= receive.buffer.hasHoles;
    }
    if (!anyHoles) {
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
    }
  }

  void _sendNack(int ssrc, List<int> sequences) {
    if (_feedback.isClosed) return;
    _feedback.add(
      DiscordNackRequest(
        mediaSsrc: ssrc,
        sequences: sequences.take(_maxNackedSequences).toList(),
      ),
    );
  }

  /// Answers whether the ask left: the rate limit refuses one inside a
  /// second of the last.
  bool _sendKeyframeAsk(_VideoReceive receive) {
    final now = _now();
    final last = receive.lastKeyframeAsk;
    if (last != null && now - last < const Duration(seconds: 1)) return false;
    receive.lastKeyframeAsk = now;
    receive.keyframeAsks++;
    _fullIntraRequests++;
    if (!_feedback.isClosed) {
      _feedback.add(
        DiscordKeyframeRequest(
          mediaSsrc: receive.ssrc,
          commandSequence: _fullIntraRequests,
        ),
      );
    }
    return true;
  }
}

/// What one sender's stream needs to recover a lost packet: the buffer that
/// waits for the retransmission, the asks in flight, and the counts the
/// recovery line reports.
final class _VideoReceive {
  _VideoReceive(this.ssrc, this.buffer);

  final int ssrc;
  final DiscordRtpReorderBuffer buffer;

  /// Holes already asked for, so a packet that exposes nothing new does not
  /// ask again ahead of the round trip.
  final Set<int> asked = {};
  Duration nextAsk = Duration.zero;

  /// A keyframe ask held back while a hole was open, or by the rate limit,
  /// to be paid when the last hole has closed and the limit allows.
  bool keyframeOwed = false;
  Duration? lastKeyframeAsk;

  int packets = 0;
  int holes = 0;
  int retransmissionsUsed = 0;
  int retransmissionsLate = 0;
  int holesGivenUp = 0;
  int keyframeAsks = 0;
  int keyframesHeld = 0;

  void resetCounters() {
    packets = 0;
    holes = 0;
    retransmissionsUsed = 0;
    retransmissionsLate = 0;
    holesGivenUp = 0;
    keyframeAsks = 0;
    keyframesHeld = 0;
  }
}
