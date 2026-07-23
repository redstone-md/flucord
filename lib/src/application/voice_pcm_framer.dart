import 'dart:typed_data';

import '../domain/voice_media.dart';

final class VoicePcmFramer {
  VoicePcmFramer({
    this.sampleRate = 48000,
    this.channels = 2,
    this.samplesPerChannel = 960,
  }) {
    if (sampleRate <= 0 || channels <= 0 || samplesPerChannel <= 0) {
      throw ArgumentError('PCM frame dimensions must be positive');
    }
  }

  static const int bytesPerSample = 2;

  final int sampleRate;
  final int channels;
  final int samplesPerChannel;
  Uint8List _pending = Uint8List(0);

  int get samplesPerFrame => samplesPerChannel * channels;
  int get bytesPerFrame => samplesPerFrame * bytesPerSample;
  int get pendingByteCount => _pending.length;

  List<Int16List> add(VoicePcmChunk chunk) {
    if (chunk.sampleRate != sampleRate || chunk.channels != channels) {
      throw StateError(
        'Expected $sampleRate Hz/$channels ch PCM, got '
        '${chunk.sampleRate} Hz/${chunk.channels} ch',
      );
    }
    final bytes = Uint8List(_pending.length + chunk.bytes.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(
        _pending.length,
        _pending.length + chunk.bytes.length,
        chunk.bytes,
      );
    final frameCount = bytes.length ~/ bytesPerFrame;
    final frames = <Int16List>[];
    for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
      final offset = frameIndex * bytesPerFrame;
      final data = ByteData.sublistView(bytes, offset, offset + bytesPerFrame);
      final samples = Int16List(samplesPerFrame);
      for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
        samples[sampleIndex] = data.getInt16(
          sampleIndex * bytesPerSample,
          Endian.little,
        );
      }
      frames.add(samples);
    }
    final consumed = frameCount * bytesPerFrame;
    _pending = Uint8List.fromList(bytes.sublist(consumed));
    return frames;
  }

  void reset() => _pending = Uint8List(0);
}
