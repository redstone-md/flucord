import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/video_decoder.dart';
import '../domain/video_encoder.dart';

/// The picture a sender sees of their own share.
///
/// The encoder's own access units, decoded on this machine (ADR-0001).
/// Nothing crosses Discord for it: a watch asked on the sender's own key is
/// never answered, so the preview is what left the encoder, and the pace line
/// is what says whether it also left the machine.
///
/// Decoded only while somebody is listening on [frames], which is the tile
/// being on screen: a sender who has moved to another channel is not paying a
/// decoder for a picture nobody draws. [start] and [stop] follow the share;
/// the listener decides whether the decoder is open in between.
///
/// A decoder needs a keyframe to start from, so frames are held back until one
/// passes; if the first frame seen is not one, the encoder is asked for one
/// rather than waiting a whole group of pictures for the next.
final class GoLiveSelfPreview extends ChangeNotifier {
  GoLiveSelfPreview({required VideoDecoderService Function() decoderFactory})
    : _decoderFactory = decoderFactory {
    _frames = StreamController.broadcast(
      onListen: _wanted,
      onCancel: _unwanted,
    );
    frames = _frames.stream;
  }

  final VideoDecoderService Function() _decoderFactory;
  late final StreamController<DecodedVideoFrame> _frames;

  /// Decoded pictures of the running share. Empty between shares, and while
  /// nobody listens.
  ///
  /// One object for the life of the preview, so a tile that re-listens when
  /// its stream changes identity keeps its subscription across rebuilds.
  late final Stream<DecodedVideoFrame> frames;

  /// The running share's output, while there is one.
  ({
    Stream<EncodedVideoFrame> encoded,
    Future<void> Function()? requestKeyframe,
  })?
  _source;

  /// Whether anything is listening on [frames].
  bool _watched = false;

  VideoDecoderService? _decoder;
  StreamSubscription<EncodedVideoFrame>? _encoded;
  StreamSubscription<DecodedVideoFrame>? _decoded;
  bool _awaitingKeyframe = true;
  bool _askedForKeyframe = false;
  Object? _error;

  /// Why there is no picture, or null while there is or could be one.
  Object? get error => _error;

  /// Whether a decoder is open: a share is running and somebody is watching.
  bool get isRunning => _decoder != null;

  /// Follows a share starting: [encoded] is decoded for as long as somebody
  /// listens, until [stop]. A decoder that will not open is reported on
  /// [error] rather than thrown: the share goes on without it.
  Future<void> start(
    Stream<EncodedVideoFrame> encoded, {
    Future<void> Function()? requestKeyframe,
  }) async {
    await _close();
    _source = (encoded: encoded, requestKeyframe: requestKeyframe);
    _error = null;
    if (_watched) await _open();
  }

  /// Follows the share ending.
  Future<void> stop() async {
    _source = null;
    await _close();
  }

  void _wanted() {
    _watched = true;
    if (_source != null) unawaited(_open());
  }

  void _unwanted() {
    _watched = false;
    unawaited(_close());
  }

  Future<void> _open() async {
    final source = _source;
    if (source == null || _decoder != null) return;
    final decoder = _decoderFactory();
    if (!decoder.isSupported) {
      _error = StateError('This build cannot decode video');
      notifyListeners();
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
        notifyListeners();
      }
      return;
    }
    // Closed while opening: the decoder is handed back here, now that it is
    // open enough to hand back.
    if (!identical(_decoder, decoder)) {
      await decoder.stop();
      return;
    }
    _decoded = decoder.frames.listen((frame) {
      if (!_frames.isClosed) _frames.add(frame);
    });
    _encoded = source.encoded.listen((frame) {
      if (_awaitingKeyframe) {
        if (!frame.isKeyframe) {
          if (!_askedForKeyframe) {
            _askedForKeyframe = true;
            unawaited(source.requestKeyframe?.call());
          }
          return;
        }
        _awaitingKeyframe = false;
      }
      unawaited(decoder.submit(frame.bytes, timestamp: frame.timestamp));
    });
  }

  Future<void> _close() async {
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

  @override
  void dispose() {
    _source = null;
    unawaited(_close());
    unawaited(_frames.close());
    super.dispose();
  }
}
