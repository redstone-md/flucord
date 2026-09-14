import 'dart:typed_data';

import '../../domain/video_encoder.dart';
import 'discord_h264_packetizer.dart';

/// What a packetised frame turned into: one RTP packet's worth of state.
final class VideoRtpPacket {
  const VideoRtpPacket({
    required this.payload,
    required this.sequence,
    required this.timestamp,
    required this.marker,
  });

  final Uint8List payload;
  final int sequence;

  /// A 90kHz clock, which is what every H.264 RTP profile uses regardless of
  /// the frame rate being captured.
  final int timestamp;

  final bool marker;
}

/// Turns encoded frames into the RTP packets Go Live carries.
///
/// Separate from the voice sender because a stream is a second connection with
/// its own SSRC and sequence space: sharing either would have the picture and
/// the room's audio overwrite each other's numbering.
final class DiscordVideoRtpSender {
  DiscordVideoRtpSender({
    required this.ssrc,
    int initialSequence = 0,
    int maxPayloadSize = DiscordH264Packetizer.maxPayloadSize,
  }) : _sequence = initialSequence & 0xffff,
       _maxPayloadSize = maxPayloadSize;

  /// The 90kHz clock rate H.264 over RTP is defined against.
  static const clockRate = 90000;

  final int ssrc;
  final int _maxPayloadSize;

  int _sequence;

  /// Where the numbering has reached, so a caller can resume one.
  int get sequence => _sequence;

  /// The packets [frame] becomes.
  ///
  /// A frame that produced no NAL units yields nothing rather than an empty
  /// packet: sending a payload-less RTP packet would advance the sequence for
  /// a picture that does not exist, and a receiver would report the gap as
  /// loss forever.
  List<VideoRtpPacket> packetsFor(EncodedVideoFrame frame) {
    final payloads = DiscordH264Packetizer.packetize(
      frame.bytes,
      maxPayloadSize: _maxPayloadSize,
    );
    if (payloads.isEmpty) return const [];
    final timestamp = timestampFor(frame.timestamp);
    return [
      for (final payload in payloads)
        VideoRtpPacket(
          payload: payload.bytes,
          sequence: _nextSequence(),
          timestamp: timestamp,
          // Every packet of one picture shares its timestamp, and only the
          // last carries the marker. That pair is how a receiver knows where
          // one frame ends and the next begins.
          marker: payload.isLast,
        ),
    ];
  }

  /// Converts a capture timestamp to the 90kHz clock, wrapped to 32 bits.
  static int timestampFor(Duration timestamp) =>
      ((timestamp.inMicroseconds * clockRate) ~/ Duration.microsecondsPerSecond)
          .toUnsigned(32);

  int _nextSequence() {
    final current = _sequence;
    _sequence = (_sequence + 1) & 0xffff;
    return current;
  }
}
