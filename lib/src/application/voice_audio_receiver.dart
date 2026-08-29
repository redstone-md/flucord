import 'dart:async';
import 'dart:typed_data';

import '../domain/voice_audio.dart';

/// Decodes remote Opus frames into PCM without opening a microphone.
final class VoiceAudioReceiver {
  VoiceAudioReceiver({
    required VoiceOpusDecoderFactory decoderFactory,
    VoiceAudioReceiverTransport? transport,
  }) : _decoderFactory = decoderFactory {
    _transport = transport;
    _remoteSubscription = _subscribe(transport);
  }

  final VoiceOpusDecoderFactory _decoderFactory;
  final StreamController<VoiceRemotePcmFrame> _remotePcm =
      StreamController.broadcast();
  final StreamController<Object> _errors = StreamController.broadcast();
  final Map<String, VoiceOpusDecoder> _decoders = {};
  final Map<String, int> _undecodableFrames = {};

  static const int _frameDurationMs = 20;
  static const int _maxConcealedFrames = 3;
  static const int _undecodableLimit = 50;

  StreamSubscription<VoiceRemoteOpusFrame>? _remoteSubscription;
  VoiceAudioReceiverTransport? _transport;
  bool _disposed = false;

  Stream<VoiceRemotePcmFrame> get remotePcm => _remotePcm.stream;
  Stream<Object> get errors => _errors.stream;

  Future<void> bindTransport(VoiceAudioReceiverTransport? transport) async {
    if (_disposed || identical(_transport, transport)) return;
    await _remoteSubscription?.cancel();
    _remoteSubscription = null;
    _disposeDecoders();
    _transport = transport;
    _remoteSubscription = _subscribe(transport);
  }

  StreamSubscription<VoiceRemoteOpusFrame>? _subscribe(
    VoiceAudioReceiverTransport? transport,
  ) => transport?.remoteAudio.listen(
    _handleRemoteOpus,
    onError: _emitError,
  );

  void _handleRemoteOpus(VoiceRemoteOpusFrame frame) {
    if (_disposed) return;
    try {
      var decoder = _decoders.putIfAbsent(
        frame.userId,
        _decoderFactory.createDecoder,
      );
      if (frame.missingFramesBefore > _maxConcealedFrames) {
        decoder.dispose();
        decoder = _decoderFactory.createDecoder();
        _decoders[frame.userId] = decoder;
      } else if (frame.missingFramesBefore > 0) {
        for (var index = 1; index < frame.missingFramesBefore; index++) {
          _emitRemotePcm(
            frame.userId,
            decoder.conceal(frameDurationMs: _frameDurationMs),
          );
        }
        _emitRemotePcm(
          frame.userId,
          decoder.decodeFec(frame.opus, frameDurationMs: _frameDurationMs),
        );
      }
      _emitRemotePcm(frame.userId, decoder.decode(frame.opus));
      _undecodableFrames.remove(frame.userId);
    } catch (error) {
      // One refused packet is not a broken room. Report a persistent failure.
      final failures = (_undecodableFrames[frame.userId] ?? 0) + 1;
      _undecodableFrames[frame.userId] = failures;
      if (failures == _undecodableLimit) _emitError(error);
    }
  }

  void _emitRemotePcm(String userId, Int16List samples) {
    if (_remotePcm.isClosed) return;
    _remotePcm.add(VoiceRemotePcmFrame(userId: userId, samples: samples));
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
    _disposed = true;
    await _remoteSubscription?.cancel();
    _remoteSubscription = null;
    _disposeDecoders();
    await _remotePcm.close();
    await _errors.close();
  }
}
