import 'dart:async';

import '../domain/video_decoder.dart';
import '../domain/video_encoder.dart';

/// The picture a sender sees of their own share.
///
/// The encoder's own access units, decoded on this machine (ADR-0001).
/// Nothing crosses Discord for it: a watch asked on the sender's own key is
/// never answered, so the preview is what left the encoder, and the pace line
/// is what says whether it also left the machine.
///
/// A decoder needs a keyframe to start from, so frames are held back until one
/// passes; if the first frame seen is not one, the encoder is asked for one
/// rather than waiting a whole group of pictures for the next.
final class GoLiveSelfPreview {
  GoLiveSelfPreview({required VideoDecoderService Function() decoderFactory})
    : _decoderFactory = decoderFactory;

  final VideoDecoderService Function() _decoderFactory;

  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();

  /// Decoded pictures of the running share. Empty between shares.
  ///
  /// One object for the life of the preview, so a tile that re-listens when
  /// its stream changes identity keeps its subscription across rebuilds.
  late final Stream<DecodedVideoFrame> frames = _frames.stream;

  VideoDecoderService? _decoder;
  StreamSubscription<EncodedVideoFrame>? _encoded;
  StreamSubscription<DecodedVideoFrame>? _decoded;
  bool _awaitingKeyframe = true;
  bool _askedForKeyframe = false;
  Object? _error;

  /// Why there is no picture, or null while there is or could be one.
  Object? get error => _error;

  bool get isRunning => _decoder != null;

  /// Starts decoding [encoded] until [stop]. A decoder that will not open is
  /// reported on [error] rather than thrown: the share goes on without it.
  Future<void> start(
    Stream<EncodedVideoFrame> encoded, {
    Future<void> Function()? requestKeyframe,
  }) async {
    await stop();
    final decoder = _decoderFactory();
    if (!decoder.isSupported) {
      _error = StateError('This build cannot decode video');
      return;
    }
    _decoder = decoder;
    _error = null;
    _awaitingKeyframe = true;
    _askedForKeyframe = false;
    try {
      await decoder.start();
    } on Object catch (error) {
      if (identical(_decoder, decoder)) {
        _decoder = null;
        _error = error;
      }
      return;
    }
    // Stopped while opening: the decoder is handed back here, now that it is
    // open enough to hand back.
    if (!identical(_decoder, decoder)) {
      await decoder.stop();
      return;
    }
    _decoded = decoder.frames.listen((frame) {
      if (!_frames.isClosed) _frames.add(frame);
    });
    _encoded = encoded.listen((frame) {
      if (_awaitingKeyframe) {
        if (!frame.isKeyframe) {
          if (!_askedForKeyframe) {
            _askedForKeyframe = true;
            unawaited(requestKeyframe?.call());
          }
          return;
        }
        _awaitingKeyframe = false;
      }
      unawaited(decoder.submit(frame.bytes, timestamp: frame.timestamp));
    });
  }

  Future<void> stop() async {
    final decoder = _decoder;
    _decoder = null;
    // Not awaited: a broadcast subscription's cancel completes on the root
    // zone, and awaiting it from inside a widget test's fake clock strands
    // everything after it.
    unawaited(_encoded?.cancel());
    unawaited(_decoded?.cancel());
    _encoded = null;
    _decoded = null;
    await decoder?.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
  }
}
