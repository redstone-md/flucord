import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_processing.dart';

/// Deterministic Opus decoder factory for audio tests.
final class FakeVoiceOpusDecoderFactory implements VoiceOpusDecoderFactory {
  int created = 0;
  int disposed = 0;

  @override
  VoiceOpusDecoder createDecoder() {
    created++;
    return _FakeVoiceOpusDecoder(this);
  }
}

/// The decoder factory above plus an encoder that hands back one byte per
/// frame, for tests that need a pipeline but not what it encodes.
final class FakeVoiceOpusCodecFactory extends FakeVoiceOpusDecoderFactory
    implements VoiceOpusCodecFactory {
  @override
  VoiceOpusEncoder createEncoder() => const _FakeVoiceOpusEncoder();
}

final class _FakeVoiceOpusEncoder implements VoiceOpusEncoder {
  const _FakeVoiceOpusEncoder();

  @override
  Uint8List encode(Int16List pcm) => Uint8List(1);

  @override
  void dispose() {}
}

/// A suppressor that records the frames it was handed and silences them, so
/// a test can tell filtered frames from raw ones by their samples.
class FakeNoiseSuppressor implements VoiceNoiseSuppressor {
  /// What every sample becomes: loud enough to pass the uplink's gate, and
  /// unlike anything a test feeds in.
  static const int cleaned = 5000;

  final List<Int16List> frames = [];
  int? channels;
  bool disposed = false;

  @override
  int get hopSize => 480;

  @override
  void process(Int16List frame, {required int channels}) {
    this.channels = channels;
    frames.add(Int16List.fromList(frame));
    frame.fillRange(0, frame.length, cleaned);
  }

  @override
  void dispose() => disposed = true;
}

final class MemoryVoiceProcessingRepository
    implements VoiceProcessingRepository {
  MemoryVoiceProcessingRepository([this.saved]);

  VoiceProcessingSettings? saved;

  /// Held back until completed by a test, to stage a slow first read.
  Completer<VoiceProcessingSettings>? pendingLoad;

  @override
  Future<VoiceProcessingSettings> load() =>
      pendingLoad?.future ??
      Future.value(saved ?? const VoiceProcessingSettings());

  @override
  Future<void> save(VoiceProcessingSettings settings) async => saved = settings;
}

final class _FakeVoiceOpusDecoder implements VoiceOpusDecoder {
  _FakeVoiceOpusDecoder(this._factory);

  final FakeVoiceOpusDecoderFactory _factory;

  @override
  Int16List decode(Uint8List opusFrame) =>
      Int16List.fromList([opusFrame.first]);

  @override
  Int16List decodeFec(Uint8List opusFrame, {int frameDurationMs = 20}) =>
      Int16List.fromList([-opusFrame.first]);

  @override
  Int16List conceal({int frameDurationMs = 20}) =>
      Int16List.fromList([-frameDurationMs]);

  @override
  void dispose() => _factory.disposed++;
}
