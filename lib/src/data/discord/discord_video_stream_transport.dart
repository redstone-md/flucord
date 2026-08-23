import 'dart:async';

import '../../domain/video_encoder.dart';
import 'discord_rtp_packet.dart';
import 'discord_video_rtp_sender.dart';

/// What actually puts a packet on the wire.
///
/// The same shape the voice client already exposes, so a stream connection can
/// be handed the voice transport's sender without either knowing about the
/// other: a stream is a second connection, but it encrypts and sends the same
/// way.
typedef VideoFrameSink = int Function(DiscordRtpFrame frame);

/// Carries encoded pictures over a Go Live connection.
///
/// This is the piece between the encoder and the socket: it packetises, builds
/// the RTP header each payload needs, and hands the result to the transport.
/// Without it the pipeline ends at a list of payloads nobody sends.
final class DiscordVideoStreamTransport {
  DiscordVideoStreamTransport({
    required int ssrc,
    required VideoFrameSink sink,
    int payloadType = DiscordRtpHeader.discordVideoPayloadType,
    int initialSequence = 0,
    int maxPayloadSize = 1200,
  }) : _sender = DiscordVideoRtpSender(
         ssrc: ssrc,
         initialSequence: initialSequence,
         maxPayloadSize: maxPayloadSize,
       ),
       _sink = sink,
       _payloadType = payloadType;

  final DiscordVideoRtpSender _sender;
  final VideoFrameSink _sink;
  final int _payloadType;

  StreamSubscription<EncodedVideoFrame>? _subscription;
  int _sentPackets = 0;
  int _sentBytes = 0;
  Object? _error;

  /// How many RTP packets have gone out, which is what a caller checks to know
  /// the stream is actually moving.
  int get sentPackets => _sentPackets;

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

  /// Sends one frame, returning how many packets it took.
  ///
  /// A failure stops the stream rather than being swallowed per packet: a
  /// transport that has gone away will not come back on the next picture, and
  /// a viewer left watching a frozen frame with no explanation is worse than
  /// one told the stream ended.
  int send(EncodedVideoFrame frame) {
    var sent = 0;
    for (final packet in _sender.packetsFor(frame)) {
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
      try {
        _sink(rtp);
      } on Object catch (error) {
        _error = error;
        unawaited(stop());
        return sent;
      }
      sent++;
      _sentPackets++;
      _sentBytes += packet.payload.length;
    }
    return sent;
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
