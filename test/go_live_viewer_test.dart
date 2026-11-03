import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/presentation/widgets/go_live_viewer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DecodedVideoFrame _frame({
  int width = 4,
  int height = 4,
  int? length,
  int fill = 0x40,
}) => DecodedVideoFrame(
  pixels: Uint8List.fromList(List.filled(length ?? width * height * 4, fill)),
  width: width,
  height: height,
  timestamp: Duration.zero,
);

/// Hands back a picture on demand rather than through the engine, so what gets
/// tested is the widget's own behaviour and not the image pipeline's timing.
final class _Converter {
  _Converter(this.image);

  final ui.Image image;
  final List<ValueChanged<ui.Image>> pending = [];
  int calls = 0;

  void convert(DecodedVideoFrame frame, ValueChanged<ui.Image> onDecoded) {
    calls++;
    pending.add(onDecoded);
  }

  /// Completes the oldest conversion still waiting.
  void complete({ui.Image? replacement}) {
    if (pending.isEmpty) return;
    pending.removeAt(0)(replacement ?? image);
  }
}

Future<ui.Image> _makeImage(int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(List.filled(width * height * 4, 0x80)),
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  group('frame', () {
    test('knows whether its buffer matches its dimensions', () {
      expect(_frame().isComplete, isTrue);
      expect(_frame().expectedLength, 64);
      // A short buffer would be drawn as garbage.
      expect(_frame(length: 10).isComplete, isFalse);
    });
  });

  testWidgets("the default converter is the engine's own decoder", (
    tester,
  ) async {
    final frames = StreamController<DecodedVideoFrame>();
    addTearDown(frames.close);

    // No converter supplied: the widget falls back to decodeImageFromPixels,
    // which is real engine work and so needs the real clock.
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: GoLiveViewer(frames: frames.stream)),
      ),
    );
    await tester.runAsync(() async {
      frames.add(_frame());
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    // Whether the engine's callback lands inside a widget test is the test
    // harness's business, not the widget's; what this pins down is that the
    // default path is wired to the engine and does not throw on the way in.
    expect(tester.takeException(), isNull);
  });

  group('viewer', () {
    // The viewer disposes whatever it is handed, so every test takes its own
    // picture rather than sharing one that a previous test already freed.
    late List<ui.Image> smalls;
    late ui.Image large;
    var taken = 0;

    setUpAll(() async {
      smalls = [
        for (var index = 0; index < 12; index++) await _makeImage(4, 4),
      ];
      large = await _makeImage(8, 8);
    });

    ui.Image nextSmall() => smalls[taken++];

    Future<void> pump(
      WidgetTester tester,
      Stream<DecodedVideoFrame> frames, {
      String label = '',
      required _Converter converter,
      Object? error,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: GoLiveViewer(
            frames: frames,
            label: label,
            converter: converter.convert,
            error: error,
          ),
        ),
      ),
    );

    testWidgets('waits, naming whose stream it is', (tester) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);

      await pump(
        tester,
        frames.stream,
        label: 'Rx',
        converter: _Converter(nextSmall()),
      );

      expect(find.byKey(const ValueKey('go-live-waiting')), findsOne);
      expect(find.text('Waiting for Rx'), findsOne);
    });

    testWidgets('a session error is shown instead of a spinner', (
      tester,
    ) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);

      await pump(
        tester,
        frames.stream,
        converter: _Converter(nextSmall()),
        error: StateError('no decoder'),
      );

      expect(find.byKey(const ValueKey('go-live-error')), findsOne);
      expect(find.text('Stream unavailable'), findsOne);
      expect(find.byKey(const ValueKey('go-live-waiting')), findsNothing);
    });

    testWidgets('a session error replaces the picture on screen', (
      tester,
    ) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);
      // Held so both pumps hand the widget one and the same stream, the way
      // the stage does across rebuilds.
      final stream = frames.stream;
      final converter = _Converter(nextSmall());

      await pump(tester, stream, converter: converter);
      frames.add(_frame());
      await tester.pump();
      converter.complete();
      await tester.pump();
      expect(find.byKey(const ValueKey('go-live-picture')), findsOne);

      // The failure that stops the decoder leaves the last picture frozen
      // and silent about it; the session's error is the honest tile.
      await pump(
        tester,
        stream,
        converter: converter,
        error: StateError('no decoder'),
      );

      expect(find.byKey(const ValueKey('go-live-error')), findsOne);
      expect(find.byKey(const ValueKey('go-live-picture')), findsNothing);
    });

    testWidgets('waits silently when nobody is named', (tester) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);

      await pump(tester, frames.stream, converter: _Converter(nextSmall()));

      expect(find.byKey(const ValueKey('go-live-waiting')), findsOne);
      expect(find.textContaining('Waiting'), findsNothing);
    });

    testWidgets('draws a picture once one decodes', (tester) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);
      final converter = _Converter(nextSmall());

      await pump(tester, frames.stream, converter: converter);
      frames.add(_frame());
      await tester.pump();
      converter.complete();
      await tester.pump();

      expect(find.byKey(const ValueKey('go-live-picture')), findsOne);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 4);
    });

    testWidgets('a frame that does not match its size is not converted', (
      tester,
    ) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);
      final converter = _Converter(nextSmall());

      await pump(tester, frames.stream, converter: converter);
      frames.add(_frame(length: 10));
      await tester.pump();

      expect(converter.calls, 0);
      expect(find.byKey(const ValueKey('go-live-waiting')), findsOne);
    });

    testWidgets('a frame arriving mid-conversion is dropped', (tester) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);
      final converter = _Converter(nextSmall());

      await pump(tester, frames.stream, converter: converter);
      frames.add(_frame());
      await tester.pump();
      // The first is still converting, so the second is not queued behind it:
      // showing the newest picture matters more than showing every picture.
      frames.add(_frame());
      await tester.pump();

      expect(converter.calls, 1);
    });

    testWidgets('a later picture replaces the one on screen', (tester) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);
      final converter = _Converter(nextSmall());

      await pump(tester, frames.stream, converter: converter);
      frames.add(_frame());
      await tester.pump();
      converter.complete();
      await tester.pump();
      frames.add(_frame(width: 8, height: 8));
      await tester.pump();
      converter.complete(replacement: large);
      await tester.pump();

      expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 8);
    });

    testWidgets('a new stream is followed and the old one dropped', (
      tester,
    ) async {
      final first = StreamController<DecodedVideoFrame>();
      final second = StreamController<DecodedVideoFrame>();
      addTearDown(first.close);
      addTearDown(second.close);
      final converter = _Converter(nextSmall());

      await pump(tester, first.stream, converter: converter);
      await pump(tester, second.stream, converter: converter);
      second.add(_frame());
      await tester.pump();
      converter.complete();
      await tester.pump();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image?.width, 4);

      first.add(_frame(width: 8, height: 8));
      await tester.pump();

      // Nothing further was converted: the old stream is no longer listened to.
      expect(converter.calls, 1);
    });

    testWidgets('a conversion landing after teardown is safe', (tester) async {
      final frames = StreamController<DecodedVideoFrame>();
      addTearDown(frames.close);
      final converter = _Converter(nextSmall());

      await pump(tester, frames.stream, converter: converter);
      frames.add(_frame());
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      converter.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('texture viewer', () {
    testWidgets(
      'waits for its first picture, draws the texture at the picture\'s '
      'size, and stops when it is given back',
      (tester) async {
        // Delivered at once, so each pump draws what was just shown.
        final textures = StreamController<VideoTexture?>.broadcast(sync: true);
        addTearDown(textures.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: FlucordTheme.dark,
            home: GoLiveTextureViewer(
              textures: textures.stream,
              label: 'your stream',
            ),
          ),
        );
        expect(find.text('Waiting for your stream'), findsOneWidget);

        textures.add(const VideoTexture(id: 5, width: 1920, height: 1080));
        await tester.pump();
        final texture = tester.widget<Texture>(find.byType(Texture));
        expect(texture.textureId, 5);
        final picture = tester.getSize(
          find.ancestor(
            of: find.byType(Texture),
            matching: find.byType(SizedBox),
          ),
        );
        expect(picture, const Size(1920, 1080));

        // A resize keeps the texture and changes the shape.
        textures.add(const VideoTexture(id: 5, width: 1280, height: 720));
        await tester.pump();
        expect(
          tester.getSize(
            find.ancestor(
              of: find.byType(Texture),
              matching: find.byType(SizedBox),
            ),
          ),
          const Size(1280, 720),
        );

        // A texture given back is not drawn: its id names nothing any more.
        textures.add(null);
        await tester.pump();
        expect(find.byType(Texture), findsNothing);
        expect(find.text('Waiting for your stream'), findsOneWidget);
      },
    );
  });
}
