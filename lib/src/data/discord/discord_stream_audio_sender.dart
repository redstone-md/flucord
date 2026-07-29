import 'dart:async';
import 'dart:typed_data';

import '../../domain/voice_audio.dart';
import '../video/system_audio_capture.dart';
import 'discord_rtp_packet.dart';
import 'discord_video_stream_transport.dart';

/// Puts a share's own sound on the stream connection.
///
/// On the stream's audio SSRC rather than the voice one. A client that reused
/// the voice uplink would play the shared application to everybody in the
/// channel whether they opened the stream or not — and would mix it into the
/// same stream as the person's microphone, where no viewer could turn one down
/// without the other.
///
/// The SSRC is the stream's own base: Discord's own client derives the audio
/// SSRC of a stream connection from the number the stream `READY` handed it,
/// exactly as the voice connection does with its own.
final class DiscordStreamAudioSender {
  DiscordStreamAudioSender({
    required int ssrc,
    required VideoFrameSink sink,
    required VoiceOpusEncoder encoder,
    this.frameSamples = 960,
  }) : _packetizer = DiscordAudioRtpPacketizer.secure(ssrc: ssrc),
       _sink = sink,
       _encoder = encoder;

  /// One Opus frame at 48 kHz is 960 samples — 20 ms, which is what every
  /// Discord client sends and what the jitter buffers on the other side are
  /// sized for.
  final int frameSamples;

  final DiscordAudioRtpPacketizer _packetizer;
  final VideoFrameSink _sink;
  final VoiceOpusEncoder _encoder;
  final List<int> _pending = [];

  StreamSubscription<SystemAudioChunk>? _subscription;
  int _sentPackets = 0;
  Object? _error;

  int get sentPackets => _sentPackets;

  /// Why sending stopped, or `null`.
  Object? get error => _error;

  int get ssrc => _packetizer.ssrc;

  /// Sends every block [chunks] produces until [stop].
  void attach(Stream<SystemAudioChunk> chunks) {
    stop();
    _error = null;
    _subscription = chunks.listen(
      accept,
      onError: (Object error) => _error = error,
    );
  }

  /// Takes one captured block.
  ///
  /// Buffered rather than sent as it arrives: WASAPI hands back whatever the
  /// endpoint had, which is not 20 ms, and an Opus frame of the wrong length
  /// is refused by the encoder rather than merely sounding wrong.
  void accept(SystemAudioChunk chunk) {
    if (chunk.channels <= 0) return;
    _pending.addAll(downmixToMono(chunk.samples, chunk.channels));
    while (_pending.length >= frameSamples) {
      final frame = Int16List.fromList(_pending.take(frameSamples).toList());
      _pending.removeRange(0, frameSamples);
      _send(frame);
    }
  }

  void _send(Int16List pcm) {
    try {
      final opus = _encoder.encode(pcm);
      if (opus.isEmpty) return;
      _sink(_packetizer.packetize(opus));
      _sentPackets++;
    } on Object catch (error) {
      // Reported rather than thrown: this runs from a capture callback, and
      // an exception there would take the capture thread's stream down with
      // it rather than merely losing a frame.
      _error = error;
    }
  }

  /// Stops sending. The encoder belongs to the caller and is left alone.
  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _pending.clear();
  }
}
