import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/go_live_self_preview.dart';
import 'package:flucord/src/application/window_visible.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_video_decoder.dart';

EncodedVideoFrame _frame({
  required bool keyframe,
  Duration timestamp = Duration.zero,
}) => EncodedVideoFrame(
  bytes: Uint8List.fromList([keyframe ? 0x65 : 0x41]),
  timestamp: timestamp,
  isKeyframe: keyframe,
);

const _texture = VideoTexture(id: 3, width: 1920, height: 1080);

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

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
    final seen = <VideoTexture>[];
    final watching = preview.textures.listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    expect(preview.isRunning, isTrue);
    expect(decoder.started, 1);
    encoded.add(_frame(keyframe: true));
    decoder.show(_texture);
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, hasLength(1));
    expect(seen, [_texture]);

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
      preview.textures.listen((_) {});

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

  test('a dropped access unit feeds only keyframes and asks for one', () async {
    final decoder = FakeVideoDecoder();
    var clock = Duration.zero;
    final preview = GoLiveSelfPreview(
      decoderFactory: () => decoder,
      now: () => clock,
    );
    addTearDown(preview.dispose);
    final encoded = StreamController<EncodedVideoFrame>.broadcast();
    addTearDown(encoded.close);
    var asked = 0;
    preview.textures.listen((_) {});
    await preview.start(encoded.stream, requestKeyframe: () async => asked++);

    encoded.add(_frame(keyframe: true));
    encoded.add(_frame(keyframe: false, timestamp: _ms(16)));
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, hasLength(2));

    // The decode fell behind and threw a unit away: everything built on it
    // is wrong. The decoder keeps its last whole picture on the texture;
    // here, the encoder is asked for the keyframe that mends it rather than
    // the tile standing still until the next one of the encoder's own, and
    // nothing that cannot mend it is fed in meanwhile.
    decoder.drop(1);
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);
    encoded.add(_frame(keyframe: false, timestamp: _ms(33)));
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, hasLength(2));

    // A second drop while that keyframe is on its way asks no second one.
    clock = _ms(500);
    decoder.drop(2);
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);

    // The keyframe, and what follows it, are fed in again.
    encoded.add(_frame(keyframe: true, timestamp: _ms(50)));
    encoded.add(_frame(keyframe: false, timestamp: _ms(66)));
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, hasLength(4));

    // A drop a second later is a new break, and asks again.
    clock = _ms(1600);
    decoder.drop(3);
    await Future<void>.delayed(Duration.zero);
    expect(asked, 2);

    // A new share starts its own count: its first drop asks at once, even
    // within a second of the last share's ask.
    await preview.start(encoded.stream, requestKeyframe: () async => asked++);
    decoder.drop(4);
    await Future<void>.delayed(Duration.zero);
    expect(asked, 3);
  });

  test('a window behind the game, or minimized, pays no decoder', () async {
    final decoder = FakeVideoDecoder();
    final window = WindowVisible();
    final preview = GoLiveSelfPreview(
      decoderFactory: () => decoder,
      window: window,
    );
    addTearDown(preview.dispose);
    final encoded = StreamController<EncodedVideoFrame>.broadcast();
    addTearDown(encoded.close);
    await preview.start(encoded.stream);
    final watching = preview.textures.listen((_) {});
    addTearDown(watching.cancel);
    await Future<void>.delayed(Duration.zero);
    expect(decoder.started, 1);

    // The sender clicks into their game: the tile is still mounted, and
    // nobody is looking at it.
    window.setFocused(false);
    await Future<void>.delayed(Duration.zero);
    expect(preview.isRunning, isFalse);
    expect(decoder.stopped, 1);
    encoded.add(_frame(keyframe: true));
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, isEmpty);

    // Back to the window: a fresh decoder, fed from the next keyframe.
    window.setFocused(true);
    await Future<void>.delayed(Duration.zero);
    expect(preview.isRunning, isTrue);
    expect(decoder.started, 2);

    // Minimized while focused is still nobody looking.
    window.setInView(false);
    await Future<void>.delayed(Duration.zero);
    expect(preview.isRunning, isFalse);
  });

  test('the share ending stops the decoder under a watching tile', () async {
    final decoder = FakeVideoDecoder();
    final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
    addTearDown(preview.dispose);
    final encoded = StreamController<EncodedVideoFrame>.broadcast();
    addTearDown(encoded.close);
    preview.textures.listen((_) {});

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
    preview.textures.listen((_) {});

    await preview.start(const Stream.empty());
    expect(preview.isRunning, isFalse);
    expect(preview.error, isStateError);
    // The tile is told, so it can show the reason instead of a black box.
    expect(told, 1);

    final unsupported = GoLiveSelfPreview(
      decoderFactory: () => FakeVideoDecoder(supported: false),
    );
    addTearDown(unsupported.dispose);
    unsupported.textures.listen((_) {});
    await unsupported.start(const Stream.empty());
    expect(unsupported.error, isStateError);
  });
}
