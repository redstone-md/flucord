import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/application/remote_camera_controller.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/voice_participant_grid.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'support/fake_video_decoder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('receiving other cameras', () {
    test('a picture is rebuilt per sender, not across them', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <FakeVideoDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = FakeVideoDecoder();
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
      // Every NAL gets the four-byte start code the sender encrypted with
      // (ADR-0005).
      expect(decoders[0].submitted.single, [
        0, 0, 0, 1, 0x65, 1, //
        0, 0, 0, 1, 2,
      ]);
      expect(decoders[1].submitted.single, [
        0, 0, 0, 1, 0x65, 9, //
        0, 0, 0, 1, 8,
      ]);
      expect(controller.packetsFrom('user-a'), 2);
      expect(controller.packetsFrom('nobody'), 0);
    });

    test(
      'a group-encrypted camera picture decrypts after reassembly',
      () async {
        final packets = StreamController<(String, DiscordRtpFrame)>();
        final decoders = <FakeVideoDecoder>[];
        final decryptions = <Uint8List>[];
        final controller = RemoteCameraController(
          packetsProvider: () => packets.stream,
          decoderFactory: () {
            final decoder = FakeVideoDecoder();
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
        expect(decryptions.single, [0, 0, 0, 1, 0x65, 1, 0, 0, 0, 1, 2]);
        expect(decoders.single.submitted, [decryptions.single]);
      },
    );

    test('a decoded picture is held for whoever sent it', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <FakeVideoDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = FakeVideoDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();
      expect(controller.isReceiving, isFalse);

      packets.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);
      decoders.single.show(_texture(width: 4));
      await Future<void>.delayed(Duration.zero);

      expect(controller.textureFor('user-a')?.width, 4);
      expect(controller.textureFor('user-b'), isNull);
      expect(controller.isReceiving, isTrue);
    });

    test('a reconnect drops the cameras built around the old socket', () async {
      final first = StreamController<(String, DiscordRtpFrame)>.broadcast();
      final second = StreamController<(String, DiscordRtpFrame)>.broadcast();
      var current = first;
      final decoders = <FakeVideoDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => current.stream,
        decoderFactory: () {
          final decoder = FakeVideoDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();
      first.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);
      decoders.single.show(_texture());
      await Future<void>.delayed(Duration.zero);
      expect(controller.textureFor('user-a'), isNotNull);

      current = second;
      controller.listen();

      // The SSRCs the old cameras were built around belong to a socket that
      // has gone, so nothing from it is still drawn.
      expect(controller.textureFor('user-a'), isNull);
      expect(decoders.single.stopped, 1);
      expect(controller.isListening, isTrue);

      // And the new socket is the one being read.
      second.add(('user-b', _frame([0x65, 2], marker: true)));
      await Future<void>.delayed(Duration.zero);
      expect(decoders.length, 2);
      expect(controller.packetsFrom('user-b'), 1);
    });

    test('stopping closes every decoder', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <FakeVideoDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = FakeVideoDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.listen();
      packets.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);

      controller.stop();

      expect(decoders.single.stopped, 1);
      expect(controller.isListening, isFalse);
      expect(controller.textureFor('user-a'), isNull);
    });

    test(
      'a camera that loses a picture asks for a keyframe and waits for an IDR',
      () async {
        final packets = StreamController<(String, DiscordRtpFrame)>();
        final decoder = FakeVideoDecoder();
        final asked = <int>[];
        var reject = true;
        final controller = RemoteCameraController(
          packetsProvider: () => packets.stream,
          decoderFactory: () => decoder,
          groupDecryptorProvider: () => (String userId, Uint8List picture) {
            if (reject) throw StateError('no key yet');
            return picture;
          },
          requestKeyframe: asked.add,
        );
        addTearDown(controller.dispose);
        controller.listen();

        // A picture that will not open, then one that references it: smeared
        // colour until the sender chooses to send a keyframe, unless asked.
        packets.add(('user-a', _frame([0x65, 1], marker: true)));
        await Future<void>.delayed(Duration.zero);
        reject = false;
        packets.add(('user-a', _frame([0x41, 2], marker: true)));
        await Future<void>.delayed(Duration.zero);

        expect(decoder.submitted, isEmpty);
        expect(asked, [41]);

        packets.add(('user-a', _frame([0x65, 3], marker: true)));
        await Future<void>.delayed(Duration.zero);
        expect(decoder.submitted, hasLength(1));
      },
    );

    test('a room where nobody sends opens no decoder at all', () async {
      var made = 0;
      final controller = RemoteCameraController(
        packetsProvider: () => const Stream<(String, DiscordRtpFrame)>.empty(),
        decoderFactory: () {
          made++;
          return FakeVideoDecoder();
        },
      );
      addTearDown(controller.dispose);

      controller.listen();
      await Future<void>.delayed(Duration.zero);

      expect(made, 0);
      expect(controller.isReceiving, isFalse);
    });

    test(
      'a camera whose sender is gone is released with its picture',
      () async {
        final packets = StreamController<(String, DiscordRtpFrame)>();
        final decoders = <FakeVideoDecoder>[];
        final controller = RemoteCameraController(
          packetsProvider: () => packets.stream,
          decoderFactory: () {
            final decoder = FakeVideoDecoder();
            decoders.add(decoder);
            return decoder;
          },
        );
        addTearDown(controller.dispose);
        controller.listen();
        packets.add(('user-a', _frame([0x65, 1], marker: true)));
        await Future<void>.delayed(Duration.zero);
        decoders.single.show(_texture());
        await Future<void>.delayed(Duration.zero);
        expect(controller.textureFor('user-a'), isNotNull);

        controller.forget('user-a');

        // Their decoder stops and the texture goes with it: a camera that
        // stayed behind for the rest of the session was a decoder and a
        // texture kept open for nobody.
        expect(decoders.single.stopped, 1);
        expect(controller.textureFor('user-a'), isNull);
        expect(controller.isReceiving, isFalse);

        // Forgetting somebody with no camera says nothing happened.
        controller.forget('user-b');
      },
    );

    test('a suspended room counts packets and opens no decoder', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <FakeVideoDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = FakeVideoDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      controller.setSuspended(true);
      controller.listen();
      packets.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);

      // Nothing to draw the picture on, so nothing to decode it with; the
      // packets are still counted, so the room knows who is sending.
      expect(decoders, isEmpty);
      expect(controller.packetsFrom('user-a'), 1);
      expect(controller.textureFor('user-a'), isNull);

      // The window back means a fresh decoder and a keyframe first.
      controller.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      expect(decoders.single.started, 1);
      expect(controller.isSuspended, isFalse);
    });

    test('the room hears when a camera texture changes, not each '
        'picture', () async {
      final packets = StreamController<(String, DiscordRtpFrame)>();
      final decoders = <FakeVideoDecoder>[];
      final controller = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = FakeVideoDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.listen();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1, reason: 'listening is announced once');

      packets.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);
      decoders.single.show(_texture(width: 4));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);

      // A texture is announced again only when it changes size; the pictures
      // themselves never reach Dart (ADR-0009).
      decoders.single.show(_texture(width: 4));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);
      decoders.single.show(_texture(width: 6));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 3);
      expect(controller.textureFor('user-a')?.width, 6);

      // Suspending gives the texture back, and the tile goes with it.
      controller.setSuspended(true);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 4);
      expect(controller.textureFor('user-a'), isNull);
    });
  });

  group('the tile', () {
    testWidgets('a camera replaces the avatar, and its absence restores it', (
      tester,
    ) async {
      VideoTexture? texture;
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
                      cameraTextureFor: (_) => texture,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('flip'),
                    onPressed: () => setState(
                      () => texture = texture == null ? _texture() : null,
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
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 11);

      await tester.tap(find.byKey(const ValueKey('flip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-camera-user-a')), findsNothing);
    });
  });
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
      payload: Uint8List.fromList(payload),
    );

/// The texture a camera is drawn on, at [width] by [height].
VideoTexture _texture({int width = 2, int height = 2}) =>
    VideoTexture(id: 11, width: width, height: height);
