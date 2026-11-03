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
    final seen = <VideoTexture?>[];
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

  test('a dropped access unit asks for a keyframe and keeps feeding', () async {
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

    // The decode fell behind and threw a unit away. The decoder keeps its
    // last whole picture until a keyframe; here, the encoder is asked for one
    // rather than the tile standing still until its own next one.
    decoder.drop(1);
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);

    // The drop is heard after the fact: the keyframe that mends it may
    // already be in, so what follows is fed on rather than held back until
    // yet another keyframe.
    encoded.add(_frame(keyframe: false, timestamp: _ms(33)));
    await Future<void>.delayed(Duration.zero);
    expect(decoder.submitted, hasLength(3));

    // A second drop while that keyframe is on its way asks no second one.
    clock = _ms(500);
    decoder.drop(2);
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);

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

  test('a tile that arrives while another still listens is given the '
      'texture at once', () async {
    final decoder = FakeVideoDecoder();
    final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
    addTearDown(preview.dispose);
    await preview.start(const Stream.empty());
    final first = <VideoTexture?>[];
    final leaving = preview.textures.listen(first.add);
    await Future<void>.delayed(Duration.zero);
    decoder.show(_texture);
    await Future<void>.delayed(Duration.zero);

    // The tile moves from the grid to the stage: the new one listens before
    // the old one lets go, and the texture's size does not change.
    final second = <VideoTexture?>[];
    final arriving = preview.textures.listen(second.add);
    addTearDown(arriving.cancel);
    await leaving.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(second, [_texture]);
    expect(decoder.started, 1);
  });

  test('a closed decoder takes its texture off the tile', () async {
    final decoder = FakeVideoDecoder();
    final window = WindowVisible();
    final preview = GoLiveSelfPreview(
      decoderFactory: () => decoder,
      window: window,
    );
    addTearDown(preview.dispose);
    await preview.start(const Stream.empty());
    final seen = <VideoTexture?>[];
    final watching = preview.textures.listen(seen.add);
    addTearDown(watching.cancel);
    await Future<void>.delayed(Duration.zero);
    decoder.show(_texture);
    await Future<void>.delayed(Duration.zero);

    // The texture is given back with the decoder; drawing its old id would
    // show a blank tile instead of a waiting one.
    window.setFocused(false);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [_texture, null]);
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

  test('coming back to the window asks for a keyframe at once', () async {
    final decoder = FakeVideoDecoder();
    final window = WindowVisible();
    var clock = Duration.zero;
    final preview = GoLiveSelfPreview(
      decoderFactory: () => decoder,
      window: window,
      now: () => clock,
    );
    addTearDown(preview.dispose);
    final encoded = StreamController<EncodedVideoFrame>.broadcast();
    addTearDown(encoded.close);
    var asked = 0;
    await preview.start(encoded.stream, requestKeyframe: () async => asked++);
    final watching = preview.textures.listen((_) {});
    addTearDown(watching.cancel);
    await Future<void>.delayed(Duration.zero);
    encoded.add(_frame(keyframe: true));
    await Future<void>.delayed(Duration.zero);

    // Alt-tab out and back: the fresh decoder must not wait up to a whole
    // group of pictures (ten seconds) for the encoder's own next keyframe.
    clock = _ms(5000);
    window.setFocused(false);
    await Future<void>.delayed(Duration.zero);
    window.setFocused(true);
    await Future<void>.delayed(Duration.zero);
    encoded.add(_frame(keyframe: false));
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);

    // Flicking back and forth within a second costs viewers one keyframe.
    window.setFocused(false);
    await Future<void>.delayed(Duration.zero);
    window.setFocused(true);
    await Future<void>.delayed(Duration.zero);
    encoded.add(_frame(keyframe: false));
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);

    // Still waiting a second later: the ask may have been lost, so it is
    // made again.
    clock = _ms(6100);
    encoded.add(_frame(keyframe: false));
    await Future<void>.delayed(Duration.zero);
    expect(asked, 2);
    encoded.add(_frame(keyframe: true));
    await Future<void>.delayed(Duration.zero);

    // Every later return asks too, not only the first one of the share.
    clock = _ms(20000);
    window.setFocused(false);
    await Future<void>.delayed(Duration.zero);
    window.setFocused(true);
    await Future<void>.delayed(Duration.zero);
    encoded.add(_frame(keyframe: false));
    await Future<void>.delayed(Duration.zero);
    expect(asked, 3);
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
