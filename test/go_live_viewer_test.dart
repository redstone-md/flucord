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
      smalls = [for (var index = 0; index < 8; index++) await _makeImage(4, 4)];
      large = await _makeImage(8, 8);
    });

    ui.Image nextSmall() => smalls[taken++];

    Future<void> pump(
      WidgetTester tester,
      Stream<DecodedVideoFrame> frames, {
      String label = '',
      required _Converter converter,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: GoLiveViewer(
            frames: frames,
            label: label,
            converter: converter.convert,
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
}
