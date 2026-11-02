import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/voice_connection.dart';

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
