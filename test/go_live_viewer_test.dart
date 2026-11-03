import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/presentation/widgets/go_live_viewer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _texture = VideoTexture(id: 5, width: 1920, height: 1080);

/// The size the picture is laid out at, before it is scaled to the tile.
Size _pictureSize(WidgetTester tester) => tester.getSize(
  find.ancestor(of: find.byType(Texture), matching: find.byType(SizedBox)),
);

void main() {
  group('frame', () {
    test('knows whether its buffer matches its dimensions', () {
      DecodedVideoFrame frame(int length) => DecodedVideoFrame(
        pixels: Uint8List(length),
        width: 4,
        height: 4,
        timestamp: Duration.zero,
      );
      expect(frame(64).isComplete, isTrue);
      expect(frame(64).expectedLength, 64);
      // A short buffer would be read as garbage.
      expect(frame(10).isComplete, isFalse);
    });
  });

  group('viewer', () {
    Future<void> pump(
      WidgetTester tester,
      Stream<VideoTexture?> textures, {
      String label = '',
      Object? error,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: GoLiveViewer(textures: textures, label: label, error: error),
        ),
      ),
    );

    /// Delivered at once, so each pump draws what was just shown.
    StreamController<VideoTexture?> textures() {
      final controller = StreamController<VideoTexture?>.broadcast(sync: true);
      addTearDown(controller.close);
      return controller;
    }

    testWidgets('waits, naming whose stream it is', (tester) async {
      await pump(tester, textures().stream, label: 'Rx');

      expect(find.byKey(const ValueKey('go-live-waiting')), findsOne);
      expect(find.text('Waiting for Rx'), findsOne);
    });

    testWidgets('waits silently when nobody is named', (tester) async {
      await pump(tester, textures().stream);

      expect(find.byKey(const ValueKey('go-live-waiting')), findsOne);
      expect(find.textContaining('Waiting'), findsNothing);
    });

    testWidgets('a session error is shown instead of a spinner', (
      tester,
    ) async {
      await pump(tester, textures().stream, error: StateError('no decoder'));

      expect(find.byKey(const ValueKey('go-live-error')), findsOne);
      expect(find.text('Stream unavailable'), findsOne);
      expect(find.byKey(const ValueKey('go-live-waiting')), findsNothing);
    });

    testWidgets('a session error replaces the picture on screen', (
      tester,
    ) async {
      final feed = textures();
      // Held so both pumps hand the widget one and the same stream, the way
      // the stage does across rebuilds.
      final stream = feed.stream;

      await pump(tester, stream);
      feed.add(_texture);
      await tester.pump();
      expect(find.byKey(const ValueKey('go-live-picture')), findsOne);

      // The failure that stops the decoder leaves the last picture frozen
      // and silent about it; the session's error is the honest tile.
      await pump(tester, stream, error: StateError('no decoder'));

      expect(find.byKey(const ValueKey('go-live-error')), findsOne);
      expect(find.byKey(const ValueKey('go-live-picture')), findsNothing);
    });

    testWidgets(
      "draws the texture at the picture's size, follows a resize, and "
      'stops when it is given back',
      (tester) async {
        final feed = textures();
        await pump(tester, feed.stream, label: 'your stream');

        feed.add(_texture);
        await tester.pump();
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 5);
        expect(_pictureSize(tester), const Size(1920, 1080));

        // A resize keeps the texture and changes the shape.
        feed.add(const VideoTexture(id: 5, width: 1280, height: 720));
        await tester.pump();
        expect(_pictureSize(tester), const Size(1280, 720));

        // A texture given back is not drawn: its id names nothing any more.
        feed.add(null);
        await tester.pump();
        expect(find.byType(Texture), findsNothing);
        expect(find.text('Waiting for your stream'), findsOneWidget);
      },
    );

    testWidgets('a new stream is followed and the old one dropped', (
      tester,
    ) async {
      final first = textures();
      final second = textures();

      await pump(tester, first.stream);
      first.add(_texture);
      await tester.pump();
      await pump(tester, second.stream);

      // The old stream's texture is not carried over to the new one.
      expect(find.byType(Texture), findsNothing);
      first.add(const VideoTexture(id: 9, width: 8, height: 8));
      await tester.pump();
      expect(find.byType(Texture), findsNothing);

      second.add(_texture);
      await tester.pump();
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 5);
    });
  });
}
