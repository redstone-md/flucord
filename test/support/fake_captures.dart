import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/domain/stream_captures.dart';

/// Windows and thumbnails a test names, in place of the platform's.
///
/// Thumbnails are answered once [thumbnailsReady] completes, so a test can
/// hold the picker while they are still being taken.
final class FakeCaptureCatalog implements CaptureCatalog {
  FakeCaptureCatalog({
    List<WindowCapture> windows = const [],
    Set<String> pictured = const {},
    Completer<void>? thumbnailsReady,
  }) : _windows = windows,
       _pictured = pictured,
       thumbnailsReady = thumbnailsReady ?? (Completer<void>()..complete());

  final List<WindowCapture> _windows;
  final Set<String> _pictured;
  final Completer<void> thumbnailsReady;

  /// Every source list a thumbnail was asked for.
  final List<List<StreamCapture>> asked = [];

  /// One opaque grey picture element as a bitmap.
  static final CaptureThumbnail picture = CaptureThumbnail.fromBgra(
    Uint8List.fromList([0x80, 0x80, 0x80, 0xff]),
    width: 1,
    height: 1,
    stride: 4,
  );

  @override
  List<WindowCapture> windows() => _windows;

  @override
  Future<Map<String, CaptureThumbnail>> thumbnails(
    List<StreamCapture> sources,
  ) async {
    asked.add(sources);
    await thumbnailsReady.future;
    return {
      for (final source in sources)
        if (_pictured.contains(source.sourceId)) source.sourceId: picture,
    };
  }
}
