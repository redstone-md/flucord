import 'dart:async';
import 'dart:typed_data';

import '../domain/voice_audio.dart';

/// Decodes remote Opus frames into PCM samples without opening a microphone.
final class VoiceAudioReceiver {
  VoiceAudioReceiver({
    required VoiceOpusDecoderFactory decoderFactory,
    String? sourceId,
  }) : _decoderFactory = decoderFactory,
       _sourceId = sourceId;

  final VoiceOpusDecoderFactory _decoderFactory;
  final String? _sourceId;
  final StreamController<VoiceRemotePcmFrame> _remotePcm =
      StreamController.broadcast();
  final StreamController<Object> _errors = StreamController.broadcast();
  final Map<String, VoiceOpusDecoder> _decoders = {};
  final Map<String, int> _undecodableFrames = {};

  /// Users whose decoder was thrown away while they left the room. Frames
  /// still carrying their name are dropped until the room has them again,
  /// so a departure cannot leave a decoder behind it.
  final Set<String> _forgotten = {};

  static const int _frameDurationMs = 20;
  static const int _maxConcealedFrames = 3;
  static const int _undecodableLimit = 50;

  StreamSubscription<VoiceRemoteOpusFrame>? _remoteSubscription;
  Future<void> _binding = Future<void>.value();
  bool _disposed = false;

  Stream<VoiceRemotePcmFrame> get remotePcm => _remotePcm.stream;
  Stream<Object> get errors => _errors.stream;

  /// Decodes [remoteAudio] from here on, dropping whatever was bound before
  /// and the decoder state that went with it. Binds are applied in order,
  /// so the last one asked for is the one that stays.
  Future<void> bind(Stream<VoiceRemoteOpusFrame>? remoteAudio) {
    final operation = _binding.then<void>((_) => _bind(remoteAudio));
    _binding = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  Future<void> _bind(Stream<VoiceRemoteOpusFrame>? remoteAudio) async {
    if (_disposed) return;
    await _remoteSubscription?.cancel();
    _remoteSubscription = null;
    _disposeDecoders();
    if (_disposed) return;
    _remoteSubscription = remoteAudio?.listen(
      _handleRemoteOpus,
      onError: _emitError,
    );
  }

  void _handleRemoteOpus(VoiceRemoteOpusFrame frame) {
    if (_disposed) return;
    if (_forgotten.contains(frame.userId)) return;
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
    _remotePcm.add(
      VoiceRemotePcmFrame(
        userId: userId,
        sourceId: _sourceId,
        samples: samples,
      ),
    );
  }

  void _emitError(Object error) {
    if (!_errors.isClosed) _errors.add(error);
  }

  /// Throws away one participant's decoder, and drops their frames until
  /// [allowDecoder] says they are back.
  ///
  /// A departure reaches this controller on one socket while the audio
  /// arrives on another: a roster on the gateway socket can be ahead of the
  /// voice socket's own SSRC pruning, so frames naming the departed can
  /// still be in flight. Decoding them would open a decoder for a sender
  /// nobody holds, and leave it there for the rest of the call.
  void forgetDecoder(String userId) {
    _decoders.remove(userId)?.dispose();
    _undecodableFrames.remove(userId);
    _forgotten.add(userId);
  }

  /// Takes a forgotten user back: the room has them again, so their frames
  /// decode instead of being dropped.
  void allowDecoder(String userId) => _forgotten.remove(userId);

  void _disposeDecoders() {
    for (final decoder in _decoders.values) {
      decoder.dispose();
    }
    _decoders.clear();
    _undecodableFrames.clear();
    _forgotten.clear();
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
