import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/domain/video_decoder.dart';

/// A decoder that records what it was handed and shows a texture when a
/// test says so. Failures are opted into per test.
final class FakeVideoDecoder implements VideoTextureDecoder {
  FakeVideoDecoder({this.supported = true, this.failStart = false});

  final bool supported;
  final bool failStart;
  final StreamController<VideoTexture> _textures = StreamController.broadcast();
  final StreamController<int> _drops = StreamController.broadcast();
  final List<Uint8List> submitted = [];
  int started = 0;
  int stopped = 0;

  void show(VideoTexture texture) => _textures.add(texture);

  /// Reports that the decode queue has dropped [total] access units so far.
  void drop(int total) => _drops.add(total);

  @override
  bool get isSupported => supported;

  @override
  Stream<VideoTexture> get textures => _textures.stream;

  @override
  Stream<int> get droppedAccessUnits => _drops.stream;

  @override
  Future<void> start() async {
    if (failStart) throw StateError('no decoder');
    started++;
  }

  @override
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp}) async =>
      submitted.add(accessUnit);

  @override
  Future<void> stop() async => stopped++;
}
