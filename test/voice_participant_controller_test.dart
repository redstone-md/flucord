import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';
import 'package:flucord/src/domain/voice_connection.dart';

void main() {
  test('tracks participant state, speaking, and departure', () async {
    final signaling = _ParticipantSignalingService();
    final controller = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);
    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

    signaling.emit(_participantState('member-1'));
    await _flushEvents();
    expect(controller.participants.single.userId, 'member-1');
    expect(controller.participants.single.isMuted, isTrue);

    signaling.emit(
      const VoiceSpeakingEvent(userId: 'member-1', ssrc: 42, speakingFlags: 1),
    );
    await _flushEvents();
    expect(controller.participants.single.isSpeaking, isTrue);
    expect(controller.participants.single.ssrc, 42);

    signaling.emit(
      const VoiceSpeakingEvent(userId: 'member-1', ssrc: 42, speakingFlags: 0),
    );
    await _flushEvents();
    expect(controller.participants.single.isSpeaking, isFalse);

    signaling.emit(const VoiceUserDisconnectedEvent('member-1'));
    await _flushEvents();
    expect(controller.participants, isEmpty);
  });

  test('removes moved users and clears roster on failure', () async {
    final signaling = _ParticipantSignalingService();
    final controller = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);
    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

    signaling.emit(_participantState('member-1'));
    signaling.emit(_participantState('member-2'));
    await _flushEvents();
    expect(controller.participants, hasLength(2));

    signaling.emit(_participantState('member-1', channelId: 'voice-2'));
    await _flushEvents();
    expect(controller.participants.map((item) => item.userId), ['member-2']);

    signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.failure),
    );
    await _flushEvents();
    expect(controller.participants, isEmpty);
  });

  test('adds the local participant from ready credentials', () async {
    final signaling = _ParticipantSignalingService();
    final controller = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => signaling,
    );
    addTearDown(controller.dispose);
    addTearDown(signaling.close);
    await controller.connect(guildId: 'guild-1', channelId: 'voice-1');

    signaling.emit(
      const VoiceCredentialsReadyEvent(
        VoiceServerCredentials(
          guildId: 'guild-1',
          channelId: 'voice-1',
          userId: 'bot-1',
          sessionId: 'session-1',
          token: 'token',
          endpoint: 'voice.example.test',
        ),
      ),
    );
    await _flushEvents();
    expect(controller.participants.single.userId, 'bot-1');

    await controller.disconnect();
    expect(controller.participants, isEmpty);
  });
}

VoiceParticipantStateEvent _participantState(
  String userId, {
  String? channelId = 'voice-1',
}) => VoiceParticipantStateEvent(
  userId: userId,
  guildId: 'guild-1',
  channelId: channelId,
  selfMuted: true,
  selfDeafened: false,
  serverMuted: false,
  serverDeafened: false,
  isStreaming: false,
  isVideoEnabled: false,
);

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _ParticipantSignalingService implements VoiceSignalingService {
  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => const {};

  @override
  Stream<void> get seatedChanges => const Stream<void>.empty();

  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  void emit(VoiceSignalingEvent event) => _events.add(event);

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async {}

  @override
  Future<void> leaveVoiceChannel(String guildId) async {}

  Future<void> close() => _events.close();
}
