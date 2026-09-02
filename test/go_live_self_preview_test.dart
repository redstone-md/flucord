import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/go_live_self_preview.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_video_decoder.dart';

EncodedVideoFrame _frame({required bool keyframe}) => EncodedVideoFrame(
  bytes: Uint8List.fromList([keyframe ? 0x65 : 0x41]),
  timestamp: Duration.zero,
  isKeyframe: keyframe,
);

void main() {
  test(
    'pictures wait for a keyframe, and the encoder is asked for one',
    () async {
      final decoder = FakeVideoDecoder();
      final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
      addTearDown(preview.dispose);
      final encoded = StreamController<EncodedVideoFrame>.broadcast();
      addTearDown(encoded.close);
      var asked = 0;

      await preview.start(encoded.stream, requestKeyframe: () async => asked++);
      expect(preview.isRunning, isTrue);
      expect(preview.error, isNull);

      // A decoder started mid-group has nothing to build on: the frame is
      // dropped and a keyframe asked for, once.
      encoded.add(_frame(keyframe: false));
      encoded.add(_frame(keyframe: false));
      await Future<void>.delayed(Duration.zero);
      expect(decoder.submitted, isEmpty);
      expect(asked, 1);

      encoded.add(_frame(keyframe: true));
      encoded.add(_frame(keyframe: false));
      await Future<void>.delayed(Duration.zero);
      expect(decoder.submitted, hasLength(2));
    },
  );

  test('decoded pictures reach the tile, and stop with the preview', () async {
    final decoder = FakeVideoDecoder();
    final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
    addTearDown(preview.dispose);
    final encoded = StreamController<EncodedVideoFrame>.broadcast();
    addTearDown(encoded.close);
    final seen = <DecodedVideoFrame>[];
    preview.frames.listen(seen.add);

    await preview.start(encoded.stream);
    decoder.emit(
      DecodedVideoFrame(
        pixels: Uint8List(4),
        width: 1,
        height: 1,
        timestamp: Duration.zero,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));

    await preview.stop();
    expect(decoder.stopped, 1);
    expect(preview.isRunning, isFalse);
    encoded.add(_frame(keyframe: true));
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, isEmpty);
  });

  test('a decoder that will not open is reported, not thrown', () async {
    final preview = GoLiveSelfPreview(
      decoderFactory: () => FakeVideoDecoder(failStart: true),
    );
    addTearDown(preview.dispose);

    await preview.start(const Stream.empty());
    expect(preview.isRunning, isFalse);
    expect(preview.error, isStateError);

    final unsupported = GoLiveSelfPreview(
      decoderFactory: () => FakeVideoDecoder(supported: false),
    );
    addTearDown(unsupported.dispose);
    await unsupported.start(const Stream.empty());
    expect(unsupported.error, isStateError);
  });
}
