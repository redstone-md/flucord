import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';

import 'support/stream_room_harness.dart';

const _friend = 'friend-1';
const _streamSource = 'stream:guild:guild-1:voice-1:friend-1';

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 1,
  address: '127.0.0.1',
  port: 1000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: [1],
  daveProtocolVersion: 0,
);

/// The room with its transport up, so sound can play.
Future<StreamRoomHarness> _connectedRoom(WidgetTester tester) async {
  final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
  await _transportReady(tester, harness);
  return harness;
}

Future<void> _transportReady(
  WidgetTester tester,
  StreamRoomHarness harness,
) async {
  harness.signaling.emit(const VoiceTransportReadyEvent(_session));
  await tester.pump();
}

/// The voice connection drops and comes back.
Future<void> _reconnect(WidgetTester tester, StreamRoomHarness harness) async {
  harness.signaling.emit(
    const VoiceSignalingStatusEvent(VoiceConnectionStatus.reconnecting),
  );
  await tester.pump();
  harness.signaling.emit(
    const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
  );
  await _transportReady(tester, harness);
}

/// One 20 ms stereo frame arrives from [sourceId], and the speaking ring it
/// lights goes out again.
Future<void> _receive(
  WidgetTester tester,
  StreamRoomHarness harness,
  String sourceId,
) async {
  harness.receivedAudio.add(
    VoiceRemotePcmFrame(
      userId: _friend,
      sourceId: sourceId,
      samples: Int16List(1920),
    ),
  );
  await tester.pump(VoiceController.speakingHangover);
}

void main() {
  group('deafen through a reconnect', () {
    testWidgets('a deafened participant hears nothing after it', (
      tester,
    ) async {
      final harness = await _connectedRoom(tester);
      await harness.voice.toggleDeafen();
      await tester.pump();

      await _reconnect(tester, harness);
      await _receive(tester, harness, _friend);
      await _receive(tester, harness, _streamSource);

      expect(harness.audio.playing, isEmpty);
      expect(harness.voice.isDeafened, isTrue);
    });

    testWidgets('undeafening afterwards brings the sound back', (tester) async {
      final harness = await _connectedRoom(tester);
      await harness.voice.toggleDeafen();
      await tester.pump();
      await _reconnect(tester, harness);

      await harness.voice.toggleDeafen();
      await tester.pump();
      await _receive(tester, harness, _friend);

      expect(harness.audio.playing, hasLength(1));
      expect(harness.voice.isDeafened, isFalse);
    });

    testWidgets('a participant who is not deafened hears the room again', (
      tester,
    ) async {
      final harness = await _connectedRoom(tester);

      await _reconnect(tester, harness);
      await _receive(tester, harness, _friend);

      expect(harness.audio.playing, hasLength(1));
    });
  });
}
