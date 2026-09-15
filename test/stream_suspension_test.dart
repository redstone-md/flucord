import 'dart:async';

import 'package:flucord/src/application/remote_camera_controller.dart';
import 'package:flucord/src/application/stream_suspension.dart';
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/window_visible.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_video_decoder.dart';
import 'support/stream_room_harness.dart';

void main() {
  test('a window that leaves the screen suspends what is being watched', () {
    final visible = WindowVisible();
    final viewer = StreamViewerController(
      repositoryProvider: () => null,
      decoderFactory: StreamRoomDecoder.new,
    );
    final cameras = RemoteCameraController(
      packetsProvider: () => const Stream.empty(),
      decoderFactory: FakeVideoDecoder.new,
    );
    addTearDown(cameras.dispose);
    final suspension = StreamSuspension(
      visible: visible,
      viewer: viewer,
      remoteCameras: cameras,
    );
    addTearDown(suspension.dispose);
    addTearDown(viewer.dispose);

    // A window nothing has moved off the screen is on it.
    expect(visible.inView, isTrue);
    expect(viewer.isSuspended, isFalse);
    expect(cameras.isSuspended, isFalse);

    visible.setInView(false);
    expect(viewer.isSuspended, isTrue);
    expect(cameras.isSuspended, isTrue);

    visible.setInView(true);
    expect(viewer.isSuspended, isFalse);
    expect(cameras.isSuspended, isFalse);
  });

  test(
    'the same rule holds camera decoding back, and lets it run again',
    () async {
      final visible = WindowVisible();
      final packets = StreamController<(String, DiscordRtpFrame)>();
      addTearDown(packets.close);
      final decoders = <FakeVideoDecoder>[];
      final cameras = RemoteCameraController(
        packetsProvider: () => packets.stream,
        decoderFactory: () {
          final decoder = FakeVideoDecoder();
          decoders.add(decoder);
          return decoder;
        },
      );
      addTearDown(cameras.dispose);
      final viewer = StreamViewerController(
        repositoryProvider: () => null,
        decoderFactory: StreamRoomDecoder.new,
      );
      addTearDown(viewer.dispose);
      final suspension = StreamSuspension(
        visible: visible,
        viewer: viewer,
        remoteCameras: cameras,
      );
      addTearDown(suspension.dispose);
      cameras.listen();
      packets.add(('user-a', _frame([0x65, 1], marker: true)));
      await Future<void>.delayed(Duration.zero);
      expect(decoders.single.started, 1);

      // Hiding the window lets the camera's decoder go; showing it again
      // opens a fresh one, the way a watched stream does.
      visible.setInView(false);
      await Future<void>.delayed(Duration.zero);
      expect(decoders.single.stopped, 1);

      visible.setInView(true);
      await Future<void>.delayed(Duration.zero);
      expect(decoders, hasLength(2));
      expect(decoders.last.started, 1);
    },
  );

  test('a rule that is disposed stops following the window', () {
    final visible = WindowVisible();
    final viewer = StreamViewerController(
      repositoryProvider: () => null,
      decoderFactory: StreamRoomDecoder.new,
    );
    final cameras = RemoteCameraController(
      packetsProvider: () => const Stream.empty(),
      decoderFactory: FakeVideoDecoder.new,
    );
    addTearDown(cameras.dispose);
    final suspension = StreamSuspension(
      visible: visible,
      viewer: viewer,
      remoteCameras: cameras,
    );
    addTearDown(viewer.dispose);

    suspension.dispose();
    visible.setInView(false);

    // The viewer is going away, and a window event must not reach a
    // controller that has already stopped listening.
    expect(viewer.isSuspended, isFalse);
    expect(cameras.isSuspended, isFalse);
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
      payload: payload,
    );
