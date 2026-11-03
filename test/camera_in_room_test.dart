import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/theme/flucord_icons.dart';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_connection.dart';

import 'support/flucord_icon_finder.dart';
import 'support/stream_room_harness.dart';

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 50,
  address: '127.0.0.1',
  port: 50000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: [],
  daveProtocolVersion: 0,
);

void main() {
  /// A server Room with a live connection and the camera on.
  Future<StreamRoomHarness> cameraRoom(WidgetTester tester) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await say(tester, room, VoiceConnectionStatus.ready);
    expect(await room.camera.turnOn(), isTrue);
    await tester.pumpAndSettle();
    return room;
  }

  group('a reconnect', () {
    testWidgets('with a new SSRC moves the camera to it and announces it', (
      tester,
    ) async {
      final room = await cameraRoom(tester);

      await say(tester, room, VoiceConnectionStatus.reconnecting);
      room.cameraTransport.audioSsrc = 50;
      await say(tester, room, VoiceConnectionStatus.ready);
      room.signaling.emit(const VoiceTransportReadyEvent(_session));
      await tester.pumpAndSettle();
      room.encoder.emit();
      await tester.pumpAndSettle();

      expect(room.cameraTransport.announcedSsrcs, [40, 50]);
      expect(room.cameraTransport.sent.last.header.ssrc, 51);
      // A viewer of the new numbering decodes nothing until a keyframe.
      expect(room.encoder.keyframes, 1);
      expect(room.encoder.started, hasLength(1));
      expect(room.camera.isOn, isTrue);
    });

    testWidgets('that resumes with the same SSRC rebuilds nothing', (
      tester,
    ) async {
      final room = await cameraRoom(tester);
      room.encoder.emit();
      await tester.pumpAndSettle();

      await say(tester, room, VoiceConnectionStatus.reconnecting);
      await say(tester, room, VoiceConnectionStatus.ready);
      room.encoder.emit();
      await tester.pumpAndSettle();

      expect(room.cameraTransport.announcedSsrcs, [40]);
      expect(room.encoder.keyframes, 0);
      expect(room.encoder.started, hasLength(1));
      // The same stream goes on: its packets keep counting up.
      expect(room.cameraTransport.sent.map((f) => f.header.sequence), [0, 1]);
    });

    testWidgets('waits for the new SSRC before it announces anything', (
      tester,
    ) async {
      final room = await cameraRoom(tester);

      // A new session has no number yet, though the old status still stands.
      room.cameraTransport.audioSsrc = null;
      await say(tester, room, VoiceConnectionStatus.ready);

      expect(room.cameraTransport.announcedSsrcs, [40]);
      expect(room.camera.isOn, isTrue);
    });
  });

  group('the media server', () {
    testWidgets('asking for a keyframe reaches the camera', (tester) async {
      final room = await cameraRoom(tester);

      room.signaling.emit(const VoiceKeyframeRequestedEvent());
      await tester.pumpAndSettle();

      expect(room.encoder.keyframes, 1);
    });

    testWidgets('asking for lost packets gets them from the camera', (
      tester,
    ) async {
      final room = await cameraRoom(tester);
      room.encoder.emit();
      await tester.pumpAndSettle();

      room.signaling.emit(
        const VoiceRetransmitRequestedEvent(ssrc: 41, sequences: [0]),
      );
      await tester.pumpAndSettle();

      // On the retransmission SSRC opcode 12 declared, the original sequence
      // leading the payload.
      final resent = room.cameraTransport.sent.last;
      expect(resent.header.ssrc, 42);
      expect(resent.payload.take(2), [0, 0]);
    });

    testWidgets('asks nothing of a camera that is off', (tester) async {
      final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
      await say(tester, room, VoiceConnectionStatus.ready);

      room.signaling
        ..emit(const VoiceKeyframeRequestedEvent())
        ..emit(const VoiceRetransmitRequestedEvent(ssrc: 41, sequences: [0]));
      await tester.pumpAndSettle();

      expect(room.encoder.keyframes, 0);
      expect(room.cameraTransport.sent, isEmpty);
    });
  });

  group('the camera flag', () {
    testWidgets('stays off the next channel of the same guild', (tester) async {
      final room = await cameraRoom(tester);
      expect(room.signaling.frames.last.selfVideo, isTrue);

      await room.voice.connect(guildId: 'guild-1', channelId: 'voice-2');
      await tester.pumpAndSettle();

      expect(room.signaling.frames.last.channelId, 'voice-2');
      expect(room.signaling.frames.last.selfVideo, isFalse);
      expectCameraEnded(room);
    });

    testWidgets('stays off a Room in another guild', (tester) async {
      final room = await cameraRoom(tester);

      await room.voice.connect(guildId: 'guild-2', channelId: 'voice-3');
      await tester.pumpAndSettle();

      expect(room.signaling.frames.last.channelId, 'voice-3');
      expect(room.signaling.frames.last.selfVideo, isFalse);
      expectCameraEnded(room);
    });

    testWidgets('stays off a call', (tester) async {
      final room = await cameraRoom(tester);

      await room.voice.connectToCall(channelId: streamRoomCall.id);
      await tester.pumpAndSettle();

      expect(room.callService.frames.last.selfVideo, isFalse);
      expectCameraEnded(room);
    });

    for (final status in [
      VoiceConnectionStatus.disconnected,
      VoiceConnectionStatus.failure,
    ]) {
      testWidgets('clears when the connection reports ${status.name}', (
        tester,
      ) async {
        final room = await cameraRoom(tester);

        await say(tester, room, status);
        await room.voice.toggleMute();
        await tester.pumpAndSettle();

        expect(room.signaling.frames.last.selfMute, isTrue);
        expect(room.signaling.frames.last.selfVideo, isFalse);
        expectCameraEnded(room);
      });
    }

    testWidgets('clears when the connection service closes', (tester) async {
      final room = await pumpStreamRoom(tester, streamRoomCall);
      await say(tester, room, VoiceConnectionStatus.ready);
      expect(await room.camera.turnOn(), isTrue);
      await tester.pumpAndSettle();

      await room.signaling.closeEvents();
      await tester.pumpAndSettle();
      await room.voice.toggleMute();
      await tester.pumpAndSettle();

      expect(room.callService.frames.last.selfMute, isTrue);
      expect(room.callService.frames.last.selfVideo, isFalse);
      expectCameraEnded(room);
    });

    testWidgets('clears when a new gateway session takes over', (tester) async {
      final room = await cameraRoom(tester);

      final replacement = room.signaling = StreamRoomSignaling();
      // On the real event loop, as giving up the old service's events only
      // finishes there, and the capture started under the fake clock lets go
      // across both.
      await tester.runAsync(room.voice.refreshSignalingService);
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);

      expect(replacement.frames.single.channelId, streamRoomVoiceChannel.id);
      expect(replacement.frames.single.selfVideo, isFalse);
      expectCameraEnded(room);
    });

    testWidgets('survives a reconnect, with the camera behind it', (
      tester,
    ) async {
      final room = await cameraRoom(tester);

      await say(tester, room, VoiceConnectionStatus.reconnecting);
      await room.voice.toggleMute();
      await say(tester, room, VoiceConnectionStatus.ready);

      expect(room.signaling.frames.last.selfMute, isTrue);
      expect(room.signaling.frames.last.selfVideo, isTrue);
      expect(room.camera.isOn, isTrue);
      expect(room.encoder.stopped, 0);
    });
  });

  group('the toolbar', () {
    testWidgets('fits every control in a narrow window', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpStreamRoom(tester, streamRoomVoiceChannel);

      for (final key in ['voice-mute', 'voice-deafen', 'voice-camera']) {
        expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('voice-disconnect')).hitTestable(),
        findsOneWidget,
      );
    });

    for (final (name, channel) in const [
      ('a server Room', streamRoomVoiceChannel),
      ('a call', streamRoomCall),
    ]) {
      testWidgets('turns the camera on and off in $name', (tester) async {
        final room = await pumpStreamRoom(tester, channel);
        await say(tester, room, VoiceConnectionStatus.ready);
        final button = find.byKey(const ValueKey('voice-camera'));

        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(room.cameraTransport.announcements, [true]);
        expect(find.byTooltip('Turn camera off'), findsOneWidget);
        expect(findFlucordIcon(FlucordIcons.camera), findsOneWidget);

        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(room.cameraTransport.announcements, [true, false]);
        expect(find.byTooltip('Turn camera on'), findsOneWidget);
      });
    }
  });
}

/// The camera went with its Room: the capture is released, and nothing was
/// said on the socket that carried it.
void expectCameraEnded(StreamRoomHarness room) {
  expect(room.camera.isOn, isFalse);
  expect(room.encoder.stopped, 1);
  expect(room.cameraTransport.announcements, [true]);
}

/// The voice connection reports [status], and the Room hears it.
Future<void> say(
  WidgetTester tester,
  StreamRoomHarness room,
  VoiceConnectionStatus status,
) async {
  room.signaling.emit(VoiceSignalingStatusEvent(status));
  await tester.pumpAndSettle();
}
