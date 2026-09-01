import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/chat_session_coordination.dart';
import 'package:flucord/src/application/direct_call_controller.dart';
import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/application/self_presence_controller.dart';
import 'package:flucord/src/application/soundboard_playback_controller.dart';
import 'package:flucord/src/application/user_profile_controller.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_service.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/soundboard_playback.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/voice_connection.dart';

import 'support/fake_video_encoder.dart';

void main() {
  test('a ready session rebinds the voice plane', () async {
    final chat = ChatController(MockChatRepository());
    final signaling = _FakeVoiceSignalingService()
      ..currentStatus = VoiceConnectionStatus.ready;
    final voice = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => signaling,
    );
    final coordination = _buildCoordination(chat: chat, voice: voice);

    await chat.load();
    await Future<void>.delayed(Duration.zero);

    expect(
      voice.connectionStatus,
      VoiceConnectionStatus.ready,
      reason: 'the voice plane follows the session into the ready transport',
    );

    coordination.dispose();
  });

  test(
    'every session notification reconciles the session-bound planes',
    () async {
      final chat = ChatController(MockChatRepository());
      final userSettings = UserSettingsController(() => _ReadySettings());
      final coordination = _buildCoordination(
        chat: chat,
        userSettings: userSettings,
      );

      expect(userSettings.isAvailable, isFalse);
      await chat.load();
      await Future<void>.delayed(Duration.zero);
      expect(
        userSettings.isAvailable,
        isTrue,
        reason: 'nothing but the session rule binds the settings plane',
      );

      coordination.dispose();
    },
  );
}

ChatSessionCoordination _buildCoordination({
  required ChatController chat,
  VoiceController? voice,
  UserSettingsController? userSettings,
}) {
  final resolvedVoice =
      voice ??
      VoiceController(
        const NoopVoiceMediaService(),
        signalingServiceProvider: () => null,
      );
  return ChatSessionCoordination(
    chat: chat,
    voice: resolvedVoice,
    directCall: DirectCallController(
      serviceProvider: () => null,
      voiceController: resolvedVoice,
    ),
    streamRtc: DiscordStreamRtcService(
      repositoryProvider: () => null,
      identityProvider: () => null,
      socketFactoryProvider: () => null,
    ),
    userSettings: userSettings ?? UserSettingsController(() => null),
    userProfile: UserProfileController(() => null),
    soundboardPlayback: SoundboardPlaybackController(
      repositoryProvider: () => null,
      connectedChannelId: () => null,
      player: _SilentSoundboardPlayer(),
    ),
    goLive: GoLiveController(
      repositoryProvider: () => null,
      capture: VideoCaptureHub(encoder: FakeVideoEncoder(supported: false)),
    ),
    selfPresence: SelfPresenceController(() => null),
  );
}

class _FakeVoiceSignalingService implements VoiceSignalingService {
  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.disconnected;

  @override
  VoiceTransportSession? currentSession;

  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  void emit(VoiceSignalingEvent event) => _events.add(event);

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => const {};

  @override
  Stream<void> get seatedChanges => const Stream.empty();

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
}

class _ReadySettings implements UserSettingsRepository {
  @override
  Stream<UserSettings> get updates => const Stream.empty();

  @override
  UserSettings? get current => const UserSettings();

  @override
  bool get isLoaded => true;

  @override
  Object? get lastWriteError => null;

  @override
  Future<UserSettings> load() async => const UserSettings();

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async {}

  @override
  Future<void> flush() async {}
}

class _SilentSoundboardPlayer implements SoundboardAudioPlayer {
  @override
  Future<void> play(String url, {double volume = 1}) async {}

  @override
  Future<void> dispose() async {}
}
