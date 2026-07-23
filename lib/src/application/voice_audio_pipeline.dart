import 'dart:async';

import '../domain/voice_audio.dart';
import '../domain/voice_media.dart';
import 'voice_pcm_framer.dart';

final class VoiceAudioPipeline {
  VoiceAudioPipeline({
    required VoiceMediaService mediaService,
    required VoiceOpusCodecFactory codecFactory,
  }) : _codecFactory = codecFactory,
       _encoder = codecFactory.createEncoder() {
    _microphoneSubscription = mediaService.microphonePcm.listen(
      _handleMicrophonePcm,
      onError: _emitError,
    );
  }

  final VoiceOpusCodecFactory _codecFactory;
  final VoiceOpusEncoder _encoder;
  final VoicePcmFramer _framer = VoicePcmFramer();
  final Map<String, VoiceOpusDecoder> _decoders = {};
  final StreamController<VoiceRemotePcmFrame> _remotePcm =
      StreamController.broadcast();
  final StreamController<Object> _errors = StreamController.broadcast();
  late final StreamSubscription<VoicePcmChunk> _microphoneSubscription;
  StreamSubscription<VoiceRemoteOpusFrame>? _remoteSubscription;
  VoiceAudioTransport? _transport;
  bool _enabled = false;
  bool _disposed = false;

  Stream<VoiceRemotePcmFrame> get remotePcm => _remotePcm.stream;
  Stream<Object> get errors => _errors.stream;
  bool get isEnabled => _enabled;

  Future<void> bindTransport(VoiceAudioTransport? transport) async {
    if (identical(_transport, transport)) return;
    await setEnabled(false);
    await _remoteSubscription?.cancel();
    _remoteSubscription = null;
    _disposeDecoders();
    _transport = transport;
    _remoteSubscription = transport?.remoteAudio.listen(
      _handleRemoteOpus,
      onError: _emitError,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    _framer.reset();
    if (!enabled) await _transport?.finishSpeaking();
  }

  void _handleMicrophonePcm(VoicePcmChunk chunk) {
    if (!_enabled || _transport == null || _disposed) return;
    try {
      for (final frame in _framer.add(chunk)) {
        _transport!.sendOpusFrame(_encoder.encode(frame));
      }
    } catch (error) {
      _emitError(error);
    }
  }

  void _handleRemoteOpus(VoiceRemoteOpusFrame frame) {
    if (_disposed) return;
    try {
      final decoder = _decoders.putIfAbsent(
        frame.userId,
        _codecFactory.createDecoder,
      );
      final samples = decoder.decode(frame.opus);
      if (!_remotePcm.isClosed) {
        _remotePcm.add(
          VoiceRemotePcmFrame(userId: frame.userId, samples: samples),
        );
      }
    } catch (error) {
      _emitError(error);
    }
  }

  void _emitError(Object error) {
    if (!_errors.isClosed) _errors.add(error);
  }

  void _disposeDecoders() {
    for (final decoder in _decoders.values) {
      decoder.dispose();
    }
    _decoders.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await setEnabled(false);
    _disposed = true;
    await _microphoneSubscription.cancel();
    await _remoteSubscription?.cancel();
    _disposeDecoders();
    _encoder.dispose();
    await _remotePcm.close();
    await _errors.close();
  }
}
