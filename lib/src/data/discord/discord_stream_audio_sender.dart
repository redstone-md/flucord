import 'dart:async';
import 'dart:typed_data';

import '../../domain/voice_audio.dart';
import '../video/system_audio_capture.dart';

/// Turns a share's own sound into the Opus frames its connection sends.
///
/// The sound goes out on the stream connection, not the voice one. A client
/// that reused the voice uplink would play the shared application to
/// everybody in the channel whether they opened the stream or not — and would
/// mix it into the same stream as the person's microphone, where no viewer
/// could turn one down without the other. Where the frames go from here is
/// the connection's business: it encrypts for the group, numbers the packets
/// and declares the speaking state exactly as a call does.
final class DiscordStreamAudioSender {
  DiscordStreamAudioSender({
    required VoiceOpusEncoder encoder,
    required void Function(Uint8List opus) sendOpus,
    this.frameSamples = 960,
  }) : _encoder = encoder,
       _sendOpus = sendOpus;

  /// One Opus frame at 48 kHz is 960 samples per channel — 20 ms, which is
  /// what every Discord client sends and what the jitter buffers on the
  /// other side are sized for.
  final int frameSamples;

  /// Stereo, as Discord sends a share's sound: the encoder was made for two
  /// channels, and a frame of any other width is refused by it.
  static const channels = 2;

  /// The only rate the encoder takes. A loopback endpoint running at another
  /// rate would need resampling, which this path does not do.
  static const sampleRate = 48000;

  final VoiceOpusEncoder _encoder;
  final void Function(Uint8List opus) _sendOpus;
  final List<int> _pending = [];

  StreamSubscription<SystemAudioChunk>? _subscription;
  int _sentPackets = 0;
  Object? _error;

  int get sentPackets => _sentPackets;

  /// Why sending stopped, or `null`.
  Object? get error => _error;

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
    if (chunk.sampleRate != sampleRate) {
      _error = StateError(
        'system audio runs at ${chunk.sampleRate} Hz, not $sampleRate',
      );
      return;
    }
    _pending.addAll(toStereo(chunk.samples, chunk.channels));
    final frameLength = frameSamples * channels;
    while (_pending.length >= frameLength) {
      final frame = Int16List.fromList(_pending.sublist(0, frameLength));
      _pending.removeRange(0, frameLength);
      _send(frame);
    }
  }

  void _send(Int16List pcm) {
    try {
      final opus = _encoder.encode(pcm);
      if (opus.isEmpty) return;
      _sendOpus(opus);
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
