import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/domain/video_decoder.dart';

/// A decoder that records what it was handed and emits a picture when a test
/// says so. Failures are opted into per test.
final class FakeVideoDecoder implements VideoDecoderService {
  FakeVideoDecoder({this.supported = true, this.failStart = false});

  final bool supported;
  final bool failStart;
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  final List<Uint8List> submitted = [];
  int started = 0;
  int stopped = 0;

  void emit(DecodedVideoFrame frame) => _frames.add(frame);

  @override
  bool get isSupported => supported;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Stream<int> get droppedAccessUnits => const Stream.empty();

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
