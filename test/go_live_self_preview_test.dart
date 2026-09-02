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

final DecodedVideoFrame _picture = DecodedVideoFrame(
  pixels: Uint8List(4),
  width: 1,
  height: 1,
  timestamp: Duration.zero,
);

void main() {
  test('nothing is decoded until somebody watches', () async {
    final decoder = FakeVideoDecoder();
    final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
    addTearDown(preview.dispose);
    final encoded = StreamController<EncodedVideoFrame>.broadcast();
    addTearDown(encoded.close);

    // The share is running, the sender is looking at another channel: no
    // decoder is paid for.
    await preview.start(encoded.stream);
    encoded.add(_frame(keyframe: true));
    await Future<void>.delayed(Duration.zero);
    expect(preview.isRunning, isFalse);
    expect(decoder.started, 0);
    expect(decoder.submitted, isEmpty);

    // The tile comes on screen: the decoder opens and pictures flow.
    final seen = <DecodedVideoFrame>[];
    final watching = preview.frames.listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    expect(preview.isRunning, isTrue);
    expect(decoder.started, 1);
    encoded.add(_frame(keyframe: true));
    decoder.emit(_picture);
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, hasLength(1));
    expect(seen, hasLength(1));

    // The tile goes away: the decoder goes with it, the share does not.
    await watching.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(preview.isRunning, isFalse);
    expect(decoder.stopped, 1);
    encoded.add(_frame(keyframe: true));
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, hasLength(1));
  });

  test(
    'pictures wait for a keyframe, and the encoder is asked for one',
    () async {
      final decoder = FakeVideoDecoder();
      final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
      addTearDown(preview.dispose);
      final encoded = StreamController<EncodedVideoFrame>.broadcast();
      addTearDown(encoded.close);
      var asked = 0;
      preview.frames.listen((_) {});

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

  test('the share ending stops the decoder under a watching tile', () async {
    final decoder = FakeVideoDecoder();
    final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
    addTearDown(preview.dispose);
    final encoded = StreamController<EncodedVideoFrame>.broadcast();
    addTearDown(encoded.close);
    preview.frames.listen((_) {});

    await preview.start(encoded.stream);
    expect(decoder.started, 1);
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
    var told = 0;
    preview.addListener(() => told++);
    preview.frames.listen((_) {});

    await preview.start(const Stream.empty());
    expect(preview.isRunning, isFalse);
    expect(preview.error, isStateError);
    // The tile is told, so it can show the reason instead of a black box.
    expect(told, 1);

    final unsupported = GoLiveSelfPreview(
      decoderFactory: () => FakeVideoDecoder(supported: false),
    );
    addTearDown(unsupported.dispose);
    unsupported.frames.listen((_) {});
    await unsupported.start(const Stream.empty());
    expect(unsupported.error, isStateError);
  });
}
