import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flucord/src/application/remote_camera_controller.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/camera_picture.dart';
import 'package:flucord/src/presentation/widgets/voice_participant_grid.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a frame with nothing in it', () {
    test('is not drawn in place of an avatar', () {
      final empty = DecodedVideoFrame(
        pixels: Uint8List(4 * 4 * 4),
        width: 4,
        height: 4,
        timestamp: Duration.zero,
      );

      // All zero is not black. Converted from YUV with no chroma it comes out
      // a flat, violent green, which is what the room showed in place of a
      // face.
      expect(empty.isComplete, isTrue);
      expect(empty.hasPicture, isFalse);
    });

    test('a picture with content is drawn', () {
      final pixels = Uint8List(4 * 4 * 4);
      pixels[pixels.length - 1] = 7;
      final frame = DecodedVideoFrame(
        pixels: pixels,
        width: 4,
        height: 4,
        timestamp: Duration.zero,
      );

      expect(frame.hasPicture, isTrue);
    });

    test('a buffer that does not match its dimensions is neither', () {
      final short = DecodedVideoFrame(
        pixels: Uint8List(8),
        width: 4,
        height: 4,
        timestamp: Duration.zero,
      );

      expect(short.hasPicture, isFalse);
    });
  });

  setUp(() async {
    // Real engine images, one per conversion: the widget disposes what it is
    // handed, and handing the same image twice would ask it to draw one that
    // has already been released.
    _images = [for (var index = 0; index < 4; index++) await _decodeOnePixel()];
    _next = 0;
  });

  group('receiving other cameras', () {
    test('a picture is rebuilt per sender, not across them', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <_FakeDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = _FakeDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();

      // Two people, interleaved on the same socket, each sending a picture in
      // two payloads. A single depacketiser would splice them together.
      packets
        ..add(('user-a', _frame([0x65, 1], marker: false)))
        ..add(('user-b', _frame([0x65, 9], marker: false)))
        ..add(('user-a', _frame([2], marker: true)))
        ..add(('user-b', _frame([8], marker: true)));
      await Future<void>.delayed(Duration.zero);

      expect(decoders.length, 2);
      // A four-byte start code opens the access unit; inside it the
      // parameter sets keep four bytes and everything else takes three, which
      // is the rule the depacketiser writes by. The second sender ends on NAL
      // type 8 — a picture parameter set — and so keeps the long one.
      expect(decoders[0].submitted.single, [0, 0, 0, 1, 0x65, 1, 0, 0, 1, 2]);
      expect(decoders[1].submitted.single, [
        0,
        0,
        0,
        1,
        0x65,
        9,
        0,
        0,
        0,
        1,
        8,
      ]);
      expect(controller.packetsFrom('user-a'), 2);
      expect(controller.packetsFrom('nobody'), 0);
    });

    test('a group-encrypted camera picture decrypts after reassembly', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <_FakeDecoder>[];
      final decryptions = <Uint8List>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = _FakeDecoder();
          decoders.add(decoder);
          return decoder;
        },
        groupDecryptorProvider: () => (String userId, Uint8List picture) {
          decryptions.add(picture);
          return picture;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();

      packets
        ..add(('user-a', _frame([0x65, 1], marker: false)))
        ..add(('user-a', _frame([2], marker: true)));
      await Future<void>.delayed(Duration.zero);

      expect(decryptions, hasLength(1));
      expect(decryptions.single, [0, 0, 0, 1, 0x65, 1, 0, 0, 1, 2]);
      expect(decoders.single.submitted, [decryptions.single]);
    });

    test('a decoded picture is held for whoever sent it', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <_FakeDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = _FakeDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();
      expect(controller.isReceiving, isFalse);

      packets.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);
      decoders.single.emit(_picture(width: 4, height: 2));
      await Future<void>.delayed(Duration.zero);

      expect(controller.frameFor('user-a')?.width, 4);
      expect(controller.frameFor('user-b'), isNull);
      expect(controller.senders, ['user-a']);
      expect(controller.isReceiving, isTrue);
    });

    test('a reconnect drops the cameras built around the old socket', () async {
      final first = StreamController<(String, DiscordRtpFrame)>.broadcast();
      final second = StreamController<(String, DiscordRtpFrame)>.broadcast();
      var current = first;
      final decoders = <_FakeDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => current.stream,
        decoderFactory: () {
          final decoder = _FakeDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();
      first.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);
      decoders.single.emit(_picture());
      await Future<void>.delayed(Duration.zero);
      expect(controller.frameFor('user-a'), isNotNull);

      current = second;
      controller.listen();

      // The SSRCs the old cameras were built around belong to a socket that
      // has gone, so nothing from it is still drawn.
      expect(controller.frameFor('user-a'), isNull);
      expect(decoders.single.stops, 1);
      expect(controller.isListening, isTrue);

      // And the new socket is the one being read.
      second.add(('user-b', _frame([0x65, 2], marker: true)));
      await Future<void>.delayed(Duration.zero);
      expect(decoders.length, 2);
      expect(controller.packetsFrom('user-b'), 1);
    });

    test('stopping closes every decoder', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <_FakeDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = _FakeDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();
      packets.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);

      controller.stop();

      expect(decoders.single.stops, 1);
      expect(controller.isListening, isFalse);
      expect(controller.senders, isEmpty);
    });

    test('a room where nobody sends opens no decoder at all', () async {
      var made = 0;
      final controller = RemoteCameraController(
        packetsProvider: () => const Stream<(String, DiscordRtpFrame)>.empty(),
        decoderFactory: () {
          made++;
          return _FakeDecoder();
        },
      );
      addTearDown(controller.dispose);

      controller.listen();
      await Future<void>.delayed(Duration.zero);

      expect(made, 0);
      expect(controller.isReceiving, isFalse);
    });
  });

  group('the tile', () {
    testWidgets('a camera replaces the avatar, and its absence restores it', (
      tester,
    ) async {
      DecodedVideoFrame? frame;
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  Expanded(
                    child: VoiceParticipantGrid(
                      participants: const [VoiceParticipant(userId: 'user-a')],
                      members: const [
                        Member(
                          id: 'user-a',
                          displayName: 'Mira',
                          initials: 'MI',
                          role: 'Member',
                          presence: Presence.online,
                          colorValue: 0xff4c9b72,
                        ),
                      ],
                      currentMemberId: 'user-b',
                      spaceId: 'guild-1',
                      cameraFrameFor: (_) => frame,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('flip'),
                    onPressed: () => setState(
                      () => frame = frame == null ? _picture() : null,
                    ),
                    child: const Text('flip'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('voice-camera-user-a')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('flip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-camera-user-a')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('flip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-camera-user-a')), findsNothing);
    });

    testWidgets('a frame is drawn, and replaced by the next one', (
      tester,
    ) async {
      final converted = <DecodedVideoFrame>[];
      var frame = _picture(width: 2, height: 2);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                CameraPicture(
                  frame: frame,
                  converter: (source, onDecoded) {
                    converted.add(source);
                    onDecoded(_image);
                  },
                ),
                TextButton(
                  key: const ValueKey('next'),
                  onPressed: () =>
                      setState(() => frame = _picture(width: 2, height: 2)),
                  child: const Text('next'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('camera-picture')), findsOneWidget);
      expect(converted.length, 1);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(converted.length, 2);
    });

    testWidgets('a frame that does not hold what it claims is not drawn', (
      tester,
    ) async {
      var converted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPicture(
            // Two pixels claimed, one supplied: the engine would read past the
            // end of the buffer.
            frame: DecodedVideoFrame(
              pixels: Uint8List(4),
              width: 2,
              height: 1,
              timestamp: Duration.zero,
            ),
            converter: (_, _) => converted++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(converted, 0);
      expect(find.byKey(const ValueKey('camera-picture')), findsNothing);
    });

    testWidgets('a conversion that lands after the frame changed is dropped', (
      tester,
    ) async {
      final pending = <ValueChanged<ui.Image>>[];
      var frame = _picture(width: 2, height: 2);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                CameraPicture(
                  frame: frame,
                  converter: (_, onDecoded) => pending.add(onDecoded),
                ),
                TextButton(
                  key: const ValueKey('next'),
                  onPressed: () =>
                      setState(() => frame = _picture(width: 2, height: 2)),
                  child: const Text('next'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      // The first conversion answers last: it belongs to a frame nobody is
      // showing any more.
      pending.first(_image);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('camera-picture')), findsNothing);

      pending.last(_image);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-picture')), findsOneWidget);
    });
  });
}

late List<ui.Image> _images;
late int _next;

/// The next unused image. Each is drawn once and disposed by the widget.
ui.Image get _image => _images[_next++];

Future<ui.Image> _decodeOnePixel() {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List(4),
    1,
    1,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  return completer.future;
}

DiscordRtpFrame _frame(List<int> payload, {required bool marker}) =>
    DiscordRtpFrame(
      header: DiscordRtpHeader(
        payloadType: DiscordRtpHeader.discordVideoPayloadType,
        sequence: 1,
        timestamp: 0,
        ssrc: 41,
        marker: marker,
      ),
      payload: payload,
    );

/// A frame with something in it.
///
/// Filled rather than zeroed: an all-zero buffer is what a decoder produces
/// when it has been handed nothing usable, and the room now treats it as no
/// picture at all rather than drawing it as flat green.
DecodedVideoFrame _picture({int width = 2, int height = 2}) =>
    DecodedVideoFrame(
      pixels: Uint8List(width * height * 4)
        ..fillRange(0, width * height * 4, 9),
      width: width,
      height: height,
      timestamp: Duration.zero,
    );

final class _FakeDecoder implements VideoDecoderService {
  final List<List<int>> submitted = [];
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  int stops = 0;

  void emit(DecodedVideoFrame frame) => _frames.add(frame);

  @override
  bool get isSupported => true;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> submit(Uint8List accessUnit, {Duration? timestamp}) async =>
      submitted.add(accessUnit);

  @override
  Future<void> stop() async => stops++;
}
