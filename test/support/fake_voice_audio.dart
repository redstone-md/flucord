import 'dart:typed_data';

import 'package:flucord/src/domain/voice_audio.dart';

/// A deterministic Opus decoder factory for receiver-boundary tests.
final class FakeVoiceOpusDecoderFactory implements VoiceOpusDecoderFactory {
  int created = 0;
  int disposed = 0;

  @override
  VoiceOpusDecoder createDecoder() {
    created++;
    return _FakeVoiceOpusDecoder(this);
  }
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
