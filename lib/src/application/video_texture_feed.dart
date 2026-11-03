import 'dart:async';

import '../domain/video_decoder.dart';

/// The texture a decoder draws on, for the tiles that show it (ADR-0009).
///
/// Each listener hears the current texture first, then every change: a tile
/// that moves from the grid to the stage listens again before the old one
/// lets go, and a texture is only announced when it changes. Null while
/// there is no picture to draw, including after the decoder closed and gave
/// its texture back.
final class VideoTextureFeed {
  VideoTextureFeed({void Function()? onListen, void Function()? onCancel})
    : _changes = StreamController.broadcast(
        onListen: onListen,
        onCancel: onCancel,
      ) {
    stream = Stream.multi((listener) {
      final current = _current;
      if (current != null) listener.add(current);
      listener.addStream(_changes.stream).whenComplete(listener.close);
    });
  }

  final StreamController<VideoTexture?> _changes;
  VideoTexture? _current;

  /// One object for the life of the feed, so a tile that listens again when
  /// its stream changes identity keeps its subscription across rebuilds.
  late final Stream<VideoTexture?> stream;

  VideoTexture? get current => _current;

  /// Whether a tile is listening.
  bool get hasListener => _changes.hasListener;

  void show(VideoTexture? texture) {
    if (texture == _current) return;
    _current = texture;
    if (!_changes.isClosed) _changes.add(texture);
  }

  Future<void> close() => _changes.close();
}
