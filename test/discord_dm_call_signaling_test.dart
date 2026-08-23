import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_session_assembler.dart';
import 'package:flucord/src/data/discord/discord_voice_signaling_service.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';

void main() {
  test('a session with no call plane refuses to join a call', () async {
    final gateway = _FakeCallGateway();
    // No callGateway: this is the shape a bot transport has.
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _UnusedSocketFactory(),
    )..setCurrentUserId('me');
    final events = <VoiceSignalingEvent>[];
    final subscription = service.voiceEvents.listen(events.add);
    addTearDown(subscription.cancel);
    addTearDown(service.close);
    addTearDown(gateway.close);

    await service.joinCall(channelId: 'dm-1');
    await _flushEvents();

    expect(gateway.callStates, isEmpty);
    expect(
      (events.single as VoiceSignalingStatusEvent).status,
      VoiceConnectionStatus.failure,
    );
  });

  test('guild voice and a DM call are independent sessions', () async {
    final gateway = _FakeCallGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _CallSocketFactory((credentials) => _InertVoiceClient()),
      callGateway: gateway,
    )..setCurrentUserId('me');
    addTearDown(service.close);
    addTearDown(gateway.close);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
    await service.joinCall(channelId: 'dm-1');
    await _flushEvents();

    // Leaving the call must not disturb the guild session, and the two never
    // collide on a key even though both are snowflakes.
    await service.leaveCall('dm-1');
    expect(gateway.callStates.last, ('dm-1', false));
    expect(gateway.updates.last.channelId, 'voice-1');

    await service.leaveVoiceChannel('guild-1');
    expect(gateway.updates.last.channelId, isNull);
  });

  test('media frames follow the session that was joined last', () async {
    final gateway = _FakeCallGateway();
    final clients = <_InertVoiceClient>[];
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _CallSocketFactory((credentials) {
        final client = _InertVoiceClient();
        clients.add(client);
        return client;
      }),
      callGateway: gateway,
    )..setCurrentUserId('me');
    addTearDown(service.close);
    addTearDown(gateway.close);

    // Nothing is connected, so there is no transport to hand a frame to.
    expect(() => service.sendOpusFrame(Uint8List(1)), throwsStateError);
    await service.finishSpeaking();

    await service.joinCall(channelId: 'dm-1');
    gateway.dispatch('VOICE_STATE_UPDATE', {
      'user_id': 'me',
      'channel_id': 'dm-1',
      'session_id': 'voice-session',
    });
    gateway.dispatch('VOICE_SERVER_UPDATE', {
      'guild_id': null,
      'channel_id': 'dm-1',
      'token': 'voice-token',
      'endpoint': 'voice.example.test',
    });
    await _flushEvents();

    expect(clients, hasLength(1));
    service.sendOpusFrame(Uint8List.fromList([1, 2]));
    await service.finishSpeaking();
    expect(clients.single.frames, hasLength(1));
    expect(clients.single.finished, isTrue);
  });

  group('session assembler', () {
    test('keys a private call on its channel', () {
      final assembler = DiscordVoiceSessionAssembler();

      expect(
        assembler.accept(
          eventName: 'VOICE_SERVER_UPDATE',
          data: const {
            'guild_id': null,
            'channel_id': 'dm-1',
            'token': 'voice-token',
            'endpoint': 'voice.example.test',
          },
          currentUserId: 'me',
        ),
        isNull,
      );

      final credentials = assembler.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {
          'user_id': 'me',
          'channel_id': 'dm-1',
          'session_id': 'voice-session',
        },
        currentUserId: 'me',
      );

      expect(credentials!.guildId, isNull);
      expect(credentials.channelId, 'dm-1');
      expect(credentials.serverId, 'dm-1');
      expect(credentials.sessionKey, const VoiceSessionKey.privateCall('dm-1'));
    });

    test('a remembered session completes from a lone server update', () {
      final assembler = DiscordVoiceSessionAssembler();
      // A consumed pairing leaves nothing behind, and the ping that asks for
      // a re-issue is answered with the server half alone.
      assembler.remember(
        key: const VoiceSessionKey.guild('guild-1'),
        channelId: 'voice-1',
        userId: 'me',
        sessionId: 'voice-session',
      );

      final credentials = assembler.accept(
        eventName: 'VOICE_SERVER_UPDATE',
        data: const {
          'guild_id': 'guild-1',
          'token': 'voice-token',
          'endpoint': 'voice.example.test',
        },
        currentUserId: 'me',
      );

      expect(credentials, isNotNull);
      expect(credentials!.sessionId, 'voice-session');
      expect(credentials.token, 'voice-token');
      // Nothing stale completes the pairing while no server update lands.
      assembler.remember(
        key: const VoiceSessionKey.guild('guild-1'),
        channelId: 'voice-1',
        userId: 'me',
        sessionId: 'voice-session',
      );
      expect(
        assembler.accept(
          eventName: 'VOICE_STATE_UPDATE',
          data: const {
            'user_id': 'me',
            'guild_id': 'guild-1',
            'channel_id': 'voice-1',
            'session_id': 'voice-session',
          },
          currentUserId: 'me',
        ),
        isNull,
      );
    });

    test('a call disconnect drops the half-built call session', () {
      final assembler = DiscordVoiceSessionAssembler()
        ..accept(
          eventName: 'VOICE_STATE_UPDATE',
          data: const {
            'user_id': 'me',
            'channel_id': 'dm-1',
            'session_id': 'voice-session',
          },
          currentUserId: 'me',
        );

      // A private-call disconnect names neither guild nor channel.
      assembler.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: const {'user_id': 'me', 'channel_id': null},
        currentUserId: 'me',
      );

      // The stale session id must not be paired with the next call's token.
      expect(
        assembler.accept(
          eventName: 'VOICE_SERVER_UPDATE',
          data: const {
            'channel_id': 'dm-1',
            'token': 'voice-token',
            'endpoint': 'voice.example.test',
          },
          currentUserId: 'me',
        ),
        isNull,
      );
    });

    test('a guild disconnect drops only that guild', () {
      final assembler = DiscordVoiceSessionAssembler()
        ..accept(
          eventName: 'VOICE_STATE_UPDATE',
          data: const {
            'user_id': 'me',
            'guild_id': 'guild-1',
            'channel_id': 'voice-1',
            'session_id': 'voice-session',
          },
          currentUserId: 'me',
        )
        ..accept(
          eventName: 'VOICE_STATE_UPDATE',
          data: const {
            'user_id': 'me',
            'guild_id': 'guild-1',
            'channel_id': null,
          },
          currentUserId: 'me',
        );

      expect(
        assembler.accept(
          eventName: 'VOICE_SERVER_UPDATE',
          data: const {
            'guild_id': 'guild-1',
            'token': 'voice-token',
            'endpoint': 'voice.example.test',
          },
          currentUserId: 'me',
        ),
        isNull,
      );
    });

    test('a server update with no credentials drops the session', () {
      final assembler = DiscordVoiceSessionAssembler()
        ..accept(
          eventName: 'VOICE_STATE_UPDATE',
          data: const {
            'user_id': 'me',
            'channel_id': 'dm-1',
            'session_id': 'voice-session',
          },
          currentUserId: 'me',
        )
        ..accept(
          eventName: 'VOICE_SERVER_UPDATE',
          data: const {'channel_id': 'dm-1', 'endpoint': ''},
          currentUserId: 'me',
        );

      expect(
        assembler.accept(
          eventName: 'VOICE_SERVER_UPDATE',
          data: const {
            'channel_id': 'dm-1',
            'token': 'voice-token',
            'endpoint': 'voice.example.test',
          },
          currentUserId: 'me',
        ),
        isNull,
        reason: 'the session id went with the dropped record',
      );
    });

    test('ignores frames it cannot attribute', () {
      final assembler = DiscordVoiceSessionAssembler();

      expect(
        assembler.accept(
          eventName: 'MESSAGE_CREATE',
          data: const {'id': 'm-1'},
          currentUserId: 'me',
        ),
        isNull,
      );
      expect(
        assembler.accept(
          eventName: 'VOICE_STATE_UPDATE',
          data: const {'user_id': 'somebody-else', 'channel_id': 'dm-1'},
          currentUserId: 'me',
        ),
        isNull,
      );
      // Neither a guild nor a channel: no session this could belong to.
      expect(
        assembler.accept(
          eventName: 'VOICE_SERVER_UPDATE',
          data: const {'token': 'voice-token', 'endpoint': 'voice.test'},
          currentUserId: 'me',
        ),
        isNull,
      );
      assembler.clearAll();
    });
  });

  group('session key', () {
    test('a guild key and a call key never collide', () {
      const guild = VoiceSessionKey.guild('same-id');
      const call = VoiceSessionKey.privateCall('same-id');

      expect(guild.isPrivateCall, isFalse);
      expect(call.isPrivateCall, isTrue);
      expect(guild, isNot(call));
      expect({guild, call}, hasLength(2));
      expect(guild, const VoiceSessionKey.guild('same-id'));
      expect(guild.hashCode, const VoiceSessionKey.guild('same-id').hashCode);
      expect('$call', contains('privateCall'));
      expect('$guild', contains('guild'));
    });
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _GuildUpdate {
  const _GuildUpdate(this.guildId, this.channelId);

  final String guildId;
  final String? channelId;
}

final class _FakeCallGateway
    implements DiscordVoiceStateGateway, DiscordCallGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();
  final List<_GuildUpdate> updates = [];
  final List<(String, bool)> callStates = [];
  final List<String> watched = [];

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  String? get sessionId => 'session-1';

  void dispatch(String name, Map<String, Object?> data) =>
      _events.add(DiscordGatewayDispatch(name: name, data: data));

  Future<void> close() => _events.close();

  @override
  void connectToCall(String channelId) => watched.add(channelId);

  @override
  void updateCallVoiceState({
    required String channelId,
    required bool connected,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => callStates.add((channelId, connected));

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => updates.add(_GuildUpdate(guildId, channelId));

  @override
  void pingVoiceServer() {}
}

final class _InertVoiceClient
    implements DiscordVoiceClient, VoiceAudioTransport {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _remoteAudio =
      StreamController.broadcast();
  final List<Uint8List> frames = [];
  bool finished = false;

  @override
  int? get audioSsrc => null;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets =>
      const Stream<(String, DiscordRtpFrame)>.empty();

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _remoteAudio.stream;

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) => false;

  @override
  int sendVideoFrame(DiscordRtpFrame frame) => 0;

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) => frame;

  @override
  void sendOpusFrame(Uint8List opusFrame) => frames.add(opusFrame);

  @override
  Future<void> finishSpeaking() async => finished = true;

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {
    await _events.close();
    await _remoteAudio.close();
  }
}

/// The seam this file does not reach: the DM-call behaviour, not the sockets
/// a call would dial.
final class _UnusedSocketFactory implements DiscordVoiceSocketFactory {
  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      throw UnsupportedError('no test here dials a call socket');

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) => throw UnsupportedError('no test here dials a stream socket');
}

final class _CallSocketFactory implements DiscordVoiceSocketFactory {
  _CallSocketFactory(this._build);

  final DiscordVoiceClient Function(VoiceServerCredentials credentials) _build;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      _build(credentials);

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) => throw UnsupportedError('the call plane dials no streams');
}
