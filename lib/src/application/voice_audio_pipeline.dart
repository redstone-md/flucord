import 'dart:async';

import '../domain/voice_audio.dart';
import '../domain/voice_media.dart';
import 'voice_audio_receiver.dart';
import 'voice_pcm_framer.dart';

final class VoiceAudioPipeline {
  VoiceAudioPipeline({
    required VoiceMediaService mediaService,
    required VoiceOpusCodecFactory codecFactory,
  }) : _encoder = codecFactory.createEncoder(),
       _receiver = VoiceAudioReceiver(decoderFactory: codecFactory) {
    _microphoneSubscription = mediaService.microphonePcm.listen(
      _handleMicrophonePcm,
      onError: _emitError,
    );
    _receiverErrorSubscription = _receiver.errors.listen(_emitError);
  }

  final VoiceOpusEncoder _encoder;
  final VoiceAudioReceiver _receiver;
  final VoicePcmFramer _framer = VoicePcmFramer();
  final StreamController<Object> _errors = StreamController.broadcast();
  late final StreamSubscription<VoicePcmChunk> _microphoneSubscription;
  late final StreamSubscription<Object> _receiverErrorSubscription;
  VoiceAudioTransport? _transport;
  bool _enabled = false;
  bool _disposed = false;

  Stream<VoiceRemotePcmFrame> get remotePcm => _receiver.remotePcm;
  Stream<Object> get errors => _errors.stream;
  bool get isEnabled => _enabled;

  Future<void> bindTransport(VoiceAudioTransport? transport) async {
    if (identical(_transport, transport)) return;
    await setEnabled(false);
    _transport = transport;
    await _receiver.bindTransport(transport);
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

  void _emitError(Object error) {
    if (!_errors.isClosed) _errors.add(error);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await setEnabled(false);
    _disposed = true;
    await _microphoneSubscription.cancel();
    await _receiverErrorSubscription.cancel();
    await _receiver.dispose();
    _encoder.dispose();
    await _errors.close();
  }
}
