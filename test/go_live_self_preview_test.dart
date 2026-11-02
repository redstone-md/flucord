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

DecodedVideoFrame _pictureAt(Duration timestamp) => DecodedVideoFrame(
  pixels: Uint8List(4),
  width: 1,
  height: 1,
  timestamp: timestamp,
);

final DecodedVideoFrame _picture = _pictureAt(Duration.zero);

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

  test(
    'a dropped access unit holds the last whole picture until a keyframe',
    () async {
      final decoder = FakeVideoDecoder();
      final preview = GoLiveSelfPreview(decoderFactory: () => decoder);
      addTearDown(preview.dispose);
      final encoded = StreamController<EncodedVideoFrame>.broadcast();
      addTearDown(encoded.close);
      var asked = 0;
      final seen = <Duration>[];
      preview.frames.listen((frame) => seen.add(frame.timestamp));
      await preview.start(encoded.stream, requestKeyframe: () async => asked++);

      encoded.add(_frame(keyframe: true));
      encoded.add(_frame(keyframe: false, timestamp: _ms(16)));
      await Future<void>.delayed(Duration.zero);
      decoder.emit(_pictureAt(Duration.zero));
      await Future<void>.delayed(Duration.zero);
      expect(seen, [Duration.zero]);

      // The decode fell behind and threw a unit away: everything built on it
      // is wrong, both what is still queued and what comes next.
      decoder.drop(1);
      await Future<void>.delayed(Duration.zero);
      decoder.emit(_pictureAt(_ms(16)));
      encoded.add(_frame(keyframe: false, timestamp: _ms(33)));
      await Future<void>.delayed(Duration.zero);
      expect(seen, [Duration.zero]);
      expect(decoder.submitted, hasLength(2));
      // The encoder's next keyframe mends it; one asked for early would cost
      // every viewer a full picture for the sender's own tile.
      expect(asked, 0);

      // A picture still in the queue when the keyframe arrives is older than
      // it, and stays hidden; the keyframe's own picture is the first shown.
      encoded.add(_frame(keyframe: true, timestamp: _ms(50)));
      await Future<void>.delayed(Duration.zero);
      expect(decoder.submitted, hasLength(3));
      decoder.emit(_pictureAt(_ms(33)));
      decoder.emit(_pictureAt(_ms(50)));
      await Future<void>.delayed(Duration.zero);
      expect(seen, [Duration.zero, _ms(50)]);
    },
  );

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
    final watching = preview.frames.listen((_) {});
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
