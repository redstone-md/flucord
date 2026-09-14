import 'dart:async';
import 'dart:typed_data';

import 'package:opus_codec/opus_codec.dart' as opus_codec;
import 'package:opus_codec_dart/opus_codec_dart.dart';

import '../domain/voice_audio.dart';

final class NativeOpusCodecFactory implements VoiceOpusCodecFactory {
  const NativeOpusCodecFactory._();

  static Future<void>? _initialization;
  static bool _initialized = false;

  static Future<NativeOpusCodecFactory> initialize() async {
    await (_initialization ??= _load());
    return const NativeOpusCodecFactory._();
  }

  static Future<void> _load() async {
    initOpus(await opus_codec.load());
    final version = getOpusVersion();
    if (!version.toLowerCase().contains('opus')) {
      throw StateError('Unexpected native Opus library: $version');
    }
    _initialized = true;
  }

  void _checkInitialized() {
    if (!_initialized) throw StateError('Native Opus is not initialized');
  }

  @override
  VoiceOpusEncoder createEncoder() {
    _checkInitialized();
    return _NativeOpusEncoder(
      SimpleOpusEncoder(
        sampleRate: 48000,
        channels: 2,
        application: Application.voip,
      ),
    );
  }

  @override
  VoiceOpusDecoder createDecoder() {
    _checkInitialized();
    return _NativeOpusDecoder(
      SimpleOpusDecoder(sampleRate: 48000, channels: 2),
    );
  }
}

final class _NativeOpusEncoder implements VoiceOpusEncoder {
  _NativeOpusEncoder(this._encoder);

  final SimpleOpusEncoder _encoder;

  @override
  Uint8List encode(Int16List pcm) {
    if (pcm.length != 1920) {
      throw ArgumentError.value(pcm.length, 'pcm.length', 'must be 1920');
    }
    return _encoder.encode(input: pcm);
  }

  @override
  void dispose() => _encoder.destroy();
}

final class _NativeOpusDecoder implements VoiceOpusDecoder {
  _NativeOpusDecoder(this._decoder);

  final SimpleOpusDecoder _decoder;

  @override
  Int16List decode(Uint8List opusFrame) => _decoder.decode(input: opusFrame);

  @override
  Int16List decodeFec(Uint8List opusFrame, {int frameDurationMs = 20}) =>
      _decoder.decode(input: opusFrame, fec: true, loss: frameDurationMs);

  @override
  Int16List conceal({int frameDurationMs = 20}) =>
      _decoder.decode(loss: frameDurationMs);

  @override
  void dispose() => _decoder.destroy();
}
