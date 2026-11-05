import 'dart:async';

import 'package:flutter/widgets.dart';

import 'nameplate_motion.dart';

/// Plays moving nameplates with Flutter's own image codec.
///
/// Discord serves each moving nameplate as an animated PNG with an alpha
/// channel (`img.png` beside `static.png`), so its clear parts stay clear.
/// The image cache keeps the decoded animation, so the next hover of the same
/// nameplate starts at once.
final class ImageNameplateVideos implements NameplateVideos {
  const ImageNameplateVideos();

  @override
  NameplateVideo open(String url) => _ImageNameplateVideo(NetworkImage(url));
}

final class _ImageNameplateVideo implements NameplateVideo {
  _ImageNameplateVideo(this._image)
    : _stream = _image.resolve(ImageConfiguration.empty) {
    _listener = ImageStreamListener(_shown, onError: _failed);
    _stream.addListener(_listener);
  }

  final ImageProvider _image;
  final ImageStream _stream;
  late final ImageStreamListener _listener;
  final _firstFrame = Completer<void>();

  /// Keeps the decoded animation alive without listening to it, so it does
  /// not tick when no [view] draws it.
  ImageStreamCompleterHandle? _handle;

  @override
  Future<void> get firstFrame => _firstFrame.future;

  void _shown(ImageInfo image, bool synchronousCall) {
    image.dispose();
    _handle ??= _stream.completer?.keepAlive();
    _stream.removeListener(_listener);
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  void _failed(Object error, StackTrace? stackTrace) {
    _stream.removeListener(_listener);
    if (!_firstFrame.isCompleted) _firstFrame.completeError(error, stackTrace);
  }

  @override
  Widget view() => Image(
    image: _image,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    excludeFromSemantics: true,
  );

  @override
  Future<void> dispose() async {
    _stream.removeListener(_listener);
    _handle?.dispose();
    _handle = null;
  }
}
