import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../domain/video_encoder.dart';
import '../../monotonic_clock.dart';
import 'discord_h264_sps.dart';
import 'discord_rtp_packet.dart';
import 'discord_video_rtp_sender.dart';

/// What actually puts a packet on the wire.
///
/// The same shape the voice client already exposes, so a stream connection can
/// be handed the voice transport's sender without either knowing about the
/// other: a stream is a second connection, but it encrypts and sends the same
/// way.
///
/// The answer is the bytes the socket took: 0 means the packet did not leave
/// this machine (a reconnect holds it back), which the transport counts as
/// unsent. A throw stops the stream.
typedef VideoFrameSink = int Function(DiscordRtpFrame frame);

/// Encrypts one whole access unit for the room's group, before packetisation.
typedef VideoFrameGroupEncryptor = Uint8List Function(Uint8List frame);

/// Carries encoded pictures over a Go Live connection.
///
/// This is the piece between the encoder and the socket: it fixes the SPS up,
/// encrypts the picture for the group when there is one, builds the RTP header
/// each payload needs, and hands the result to the transport. Without it the
/// pipeline ends at a list of payloads nobody sends.
final class DiscordVideoStreamTransport {
  DiscordVideoStreamTransport({
    required int ssrc,
    required VideoFrameSink sink,
    VideoFrameGroupEncryptor? groupEncryptor,
    int? rtxSsrc,
    int payloadType = DiscordRtpHeader.discordVideoPayloadType,
    int rtxPayloadType = DiscordRtpHeader.discordVideoRtxPayloadType,
    int initialSequence = 0,
    int maxPayloadSize = 1200,
    int pacingBitsPerSecond = 0,
    int maxQueuedPackets = maxQueuedPackets,
    Duration Function() now = monotonicNow,
  }) : _sender = DiscordVideoRtpSender(
         ssrc: ssrc,
         initialSequence: initialSequence,
         maxPayloadSize: maxPayloadSize,
       ),
       _sink = sink,
       _groupEncryptor = groupEncryptor,
       _rtxSsrc = rtxSsrc ?? ssrc + 1,
       _payloadType = payloadType,
       _rtxPayloadType = rtxPayloadType,
       _paceBytesPerSecond = pacingBitsPerSecond * paceMultiplier / 8,
       _maxQueuedPackets = maxQueuedPackets,
       _now = now;

  /// How many sent packets are kept for retransmission: four seconds at
  /// the packet rate of a 720p share, which is longer than any viewer waits
  /// for a missing packet. A power of two, so a sequence indexes it by mask.
  static const historySize = 1024;

  /// The wire rate packets are let out at, as a multiple of the encoder's
  /// bitrate: fast enough that a keyframe several times the size of an
  /// ordinary picture drains in a few frame intervals, slow enough that a
  /// picture is not one burst. The multiple WebRTC's pacer uses.
  static const paceMultiplier = 2.5;

  /// How often the queue is let out. A coarse system timer only makes each
  /// release bigger, because the budget is counted from the clock rather
  /// than from the ticks.
  static const paceInterval = Duration(milliseconds: 5);

  /// The most packets the pacing queue holds: room for one whole keyframe
  /// (about a hundred packets of a 720p picture) plus several ordinary
  /// pictures around it, and no more.
  ///
  /// A pace the bitrate adapter has lowered below what the encoder keeps
  /// producing makes the queue grow forever, and packets leave hours after
  /// the moment a watcher could have used them. So the bound is enforced,
  /// not hoped for: a packet that does not fit drops the oldest picture in
  /// the queue to make room. What was dropped shows in [takeWindow], and
  /// the sender's pace line reports it.
  static const maxQueuedPackets = 256;

  final DiscordVideoRtpSender _sender;
  final VideoFrameSink _sink;
  final VideoFrameGroupEncryptor? _groupEncryptor;
  final int _rtxSsrc;
  final int _payloadType;
  final int _rtxPayloadType;

  /// Pacing: a picture's packets are queued and let out at
  /// [_paceBytesPerSecond] rather than in one burst. Zero sends at once.
  ///
  /// A 720p picture is ten packets and a keyframe can be a hundred; put on
  /// the wire in one loop they arrive at the uplink faster than it drains,
  /// and the ones the router's queue has no room for are the loss the far
  /// end reports. The budget is a token bucket: it grows with the clock,
  /// each packet spends its size, and it never builds up while nothing is
  /// queued, so a frame after silence is still let out one packet at a time.
  double _paceBytesPerSecond;
  final int _maxQueuedPackets;
  final Duration Function() _now;

  /// Follows the encoder's bitrate when it changes mid-stream: the pace is
  /// a multiple of it, and a pace left at the old rate would let a lowered
  /// bitrate out in the bursts the lowering was meant to end.
  set pacingBitsPerSecond(int bitsPerSecond) {
    _paceBytesPerSecond = bitsPerSecond * paceMultiplier / 8;
  }

  /// Two numbers about this window of the stream, for the pace log: the
  /// longest gap between two pictures arriving to be sent (a stall in the
  /// encoder or in this isolate), the deepest the pacing queue got (a
  /// pace that is not keeping up), and how many packets the bound threw
  /// away (a pace left below the encoder for a whole window). Reading them
  /// starts the next window.
  ({Duration maxSendGap, int maxQueued, int droppedPackets}) takeWindow() {
    final window = (
      maxSendGap: _maxSendGap,
      maxQueued: _maxQueued,
      droppedPackets: _droppedInWindow,
    );
    _maxSendGap = Duration.zero;
    _maxQueued = 0;
    _droppedInWindow = 0;
    return window;
  }

  Duration? _lastSendAt;
  Duration _maxSendGap = Duration.zero;
  int _maxQueued = 0;
  int _droppedInWindow = 0;

  /// Keeps the RTP clock running forward across an encoder restart.
  ///
  /// An encoder counts from zero, so a share whose quality changed hands
  /// over pictures stamped before the ones already sent, and a receiver
  /// treats a clock that jumped back as pictures from the past. The offset
  /// puts the new encoder's first picture one frame after the last one sent.
  Duration _timestampOffset = Duration.zero;
  Duration? _lastRawTimestamp;
  Duration _lastTimestamp = Duration.zero;

  /// One frame at the lowest rate a share is sent at: far enough forward to
  /// be a new picture, not so far that a viewer waits for it.
  static const _restartGap = Duration(milliseconds: 33);

  EncodedVideoFrame _continuous(EncodedVideoFrame frame) {
    final lastRaw = _lastRawTimestamp;
    if (lastRaw != null && frame.timestamp < lastRaw) {
      _timestampOffset = _lastTimestamp + _restartGap - frame.timestamp;
    }
    _lastRawTimestamp = frame.timestamp;
    _lastTimestamp = frame.timestamp + _timestampOffset;
    if (_timestampOffset == Duration.zero) return frame;
    return EncodedVideoFrame(
      bytes: frame.bytes,
      timestamp: _lastTimestamp,
      isKeyframe: frame.isKeyframe,
    );
  }

  final Queue<DiscordRtpFrame> _queue = Queue();
  double _budgetBytes = 0;
  Duration? _budgetRead;
  Timer? _paceTimer;

  /// The packets that went out most recently, by sequence, as the wire saw
  /// them: group-encrypted already, so a retransmission is a copy.
  final List<DiscordRtpFrame?> _history = List.filled(historySize, null);
  int _rtxSequence = 0;

  StreamSubscription<EncodedVideoFrame>? _subscription;
  int _sentPackets = 0;
  int _sentFrames = 0;
  int _sentBytes = 0;
  int _retransmittedPackets = 0;
  Object? _error;

  /// How many RTP packets have gone out, which is what a caller checks to know
  /// the stream is actually moving.
  int get sentPackets => _sentPackets;

  /// How many packets went out a second time because the far end asked.
  int get retransmittedPackets => _retransmittedPackets;

  /// How many pictures have gone out, which is what says the encoder and the
  /// frame path are keeping pace.
  int get sentFrames => _sentFrames;

  int get sentBytes => _sentBytes;

  /// Why sending stopped, or `null`.
  Object? get error => _error;

  int get ssrc => _sender.ssrc;

  /// Sends every frame [frames] produces until [stop].
  void attach(Stream<EncodedVideoFrame> frames) {
    _subscription?.cancel();
    _error = null;
    _subscription = frames.listen(
      send,
      onError: (Object error) {
        _error = error;
      },
    );
  }

  /// How many packets are waiting for pacing budget.
  int get queuedPackets => _queue.length;

  /// Sends one frame, returning how many packets it took.
  ///
  /// With pacing, "sent" means accepted for the wire: the packets leave over
  /// the next few milliseconds. A failure stops the stream rather than being
  /// swallowed per packet: a transport that has gone away will not come back
  /// on the next picture, and a viewer left watching a frozen frame with no
  /// explanation is worse than one told the stream ended.
  int send(EncodedVideoFrame frame) {
    final now = _now();
    final last = _lastSendAt;
    if (last != null) {
      final gap = now - last;
      if (gap > _maxSendGap) _maxSendGap = gap;
    }
    _lastSendAt = now;
    var sent = 0;
    for (final packet in _sender.packetsFor(_prepare(_continuous(frame)))) {
      final rtp = DiscordRtpFrame(
        header: DiscordRtpHeader(
          sequence: packet.sequence,
          timestamp: packet.timestamp,
          ssrc: _sender.ssrc,
          payloadType: _payloadType,
          marker: packet.marker,
        ),
        payload: packet.payload,
      );
      if (_paceBytesPerSecond > 0) {
        _makeRoom();
        _queue.add(rtp);
      } else if (!_putOnWire(rtp)) {
        return sent;
      }
      sent++;
    }
    if (sent > 0) _sentFrames++;
    if (_queue.length > _maxQueued) _maxQueued = _queue.length;
    if (_queue.isNotEmpty) _release();
    return sent;
  }

  /// Lets out as many queued packets as the budget covers, and keeps the
  /// timer running while any are left.
  void _release() {
    final now = _now();
    final read = _budgetRead;
    if (read != null) {
      _budgetBytes +=
          (now - read).inMicroseconds *
          _paceBytesPerSecond /
          Duration.microsecondsPerSecond;
    }
    _budgetRead = now;
    // A packet goes when the budget is not in debt: the first one after
    // silence leaves at once and puts the bucket in debt for its size.
    while (_queue.isNotEmpty && _budgetBytes >= 0) {
      final rtp = _queue.removeFirst();
      if (!_putOnWire(rtp)) return;
      _budgetBytes -= rtp.payload.length;
    }
    if (_queue.isEmpty) {
      _paceTimer?.cancel();
      _paceTimer = null;
      // No saving up while idle: silence earns no burst.
      if (_budgetBytes > 0) _budgetBytes = 0;
      return;
    }
    _paceTimer ??= Timer.periodic(paceInterval, (_) => _release());
  }

  /// Makes room for one more packet at the bound, by giving up the oldest
  /// picture in the queue.
  ///
  /// The head is what goes: it has waited longest, and once the queue is
  /// full a packet leaves late enough that a fresh one behind it is worth
  /// more. The drop stops at a picture boundary (the packet with the marker
  /// bit), so a queued picture is given up whole; the head may be the tail
  /// of a picture whose front already left, and its remainder is unusable
  /// anyway. A watcher misses what was dropped until the next keyframe,
  /// which the media server asks for when it cannot decode.
  void _makeRoom() {
    while (_queue.length >= _maxQueuedPackets && _queue.isNotEmpty) {
      DiscordRtpFrame dropped;
      do {
        dropped = _queue.removeFirst();
        _droppedInWindow++;
      } while (!dropped.header.marker && _queue.isNotEmpty);
    }
  }

  /// One packet of a picture onto the wire, recorded for retransmission when
  /// it actually went out. False only when the stream has stopped.
  bool _putOnWire(DiscordRtpFrame rtp) {
    final handed = _put(rtp);
    if (handed < 0) return false;
    if (handed > 0) {
      _history[rtp.header.sequence & (historySize - 1)] = rtp;
      _sentPackets++;
      _sentBytes += handed;
    }
    return true;
  }

  /// Sends [sequences] again, answering how many were still held.
  ///
  /// As RFC 4588 retransmissions: on the retransmission SSRC and payload
  /// type, numbered in their own sequence, with the original sequence
  /// leading the payload so the receiver can put the packet back where it
  /// belongs. A sequence that has left the history, or was never sent, is
  /// skipped: the viewer has moved on from it already. Retransmissions skip
  /// the pacing queue: a viewer is already waiting on them, and they are a
  /// few packets, not a picture.
  int retransmit(Iterable<int> sequences) {
    var sent = 0;
    for (final sequence in sequences) {
      final held = _history[sequence & (historySize - 1)];
      if (held == null || held.header.sequence != sequence) continue;
      final rtx = DiscordRtpFrame(
        header: DiscordRtpHeader(
          sequence: _rtxSequence,
          timestamp: held.header.timestamp,
          ssrc: _rtxSsrc,
          payloadType: _rtxPayloadType,
          marker: held.header.marker,
        ),
        payload: [sequence >> 8, sequence & 0xff, ...held.payload],
      );
      final handed = _put(rtx);
      if (handed < 0) return sent;
      if (handed == 0) continue;
      _rtxSequence = (_rtxSequence + 1) & 0xffff;
      sent++;
      _retransmittedPackets++;
    }
    return sent;
  }

  /// One packet to the sink. Answers the bytes it handed to the wire: 0 when
  /// it held the packet back (a reconnect does), and -1 when it threw, which
  /// stops the stream. Only handed packets are counted, or the pace line
  /// reports traffic that never left the machine.
  int _put(DiscordRtpFrame rtp) {
    try {
      return _sink(rtp);
    } on Object catch (error) {
      _error = error;
      unawaited(stop());
      return -1;
    }
  }

  /// The two whole-frame steps that must happen before packetisation.
  ///
  /// The SPS rewrite is a Discord requirement on the bytes every receiver
  /// parses. The group encryption then needs the complete picture: a receiver
  /// reassembles a frame from its RTP packets and decrypts it once, so
  /// encrypting per packet would hand every viewer fragments of different
  /// ciphertexts. With no group to encrypt for, the picture goes out as it
  /// was rewritten.
  EncodedVideoFrame _prepare(EncodedVideoFrame frame) {
    final bytes = DiscordH264Sps.rewriteAccessUnit(frame.bytes);
    final encryptor = _groupEncryptor;
    if (encryptor == null) return frame.withBytes(bytes);
    return frame.withBytes(Uint8List.fromList(encryptor(bytes)));
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    _paceTimer?.cancel();
    _paceTimer = null;
    _queue.clear();
    await subscription?.cancel();
  }
}
