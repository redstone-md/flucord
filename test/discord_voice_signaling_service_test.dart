import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_signaling_service.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_dave.dart';

void main() {
  test('refuses to join before Discord Gateway READY', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      nativeDaveService: _CapabilityOnlyDaveService(),
    );
    final events = <VoiceSignalingEvent>[];
    final subscription = service.voiceEvents.listen(events.add);
    addTearDown(subscription.cancel);
    addTearDown(service.close);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
    await _flushEvents();

    expect(gateway.updates, isEmpty);
    expect(
      (events.single as VoiceSignalingStatusEvent).status,
      VoiceConnectionStatus.failure,
    );
  });

  test('assembles credentials and starts one DAVE voice client', () async {
    final gateway = _FakeMainGateway();
    final clients = <_FakeVoiceClient>[];
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      nativeDaveService: _CapabilityOnlyDaveService(),
      voiceClientFactory: (credentials, daveService) {
        final client = _FakeVoiceClient(credentials);
        clients.add(client);
        return client;
      },
    )..setCurrentUserId('bot-1');
    final events = <VoiceSignalingEvent>[];
    final subscription = service.voiceEvents.listen(events.add);
    addTearDown(subscription.cancel);
    addTearDown(service.close);

    await service.joinVoiceChannel(
      guildId: 'guild-1',
      channelId: 'voice-1',
      selfMute: true,
    );
    gateway.dispatch('VOICE_SERVER_UPDATE', {
      'guild_id': 'guild-1',
      'token': 'voice-token',
      'endpoint': 'voice.example.test',
    });
    gateway.dispatch('VOICE_STATE_UPDATE', {
      'guild_id': 'guild-1',
      'channel_id': 'voice-1',
      'user_id': 'bot-1',
      'session_id': 'session-1',
    });
    await _flushEvents();

    expect(gateway.updates.single.guildId, 'guild-1');
    expect(gateway.updates.single.channelId, 'voice-1');
    expect(gateway.updates.single.selfMute, isTrue);
    expect(clients, hasLength(1));
    expect(clients.single.connected, isTrue);
    expect(clients.single.credentials.sessionId, 'session-1');
    expect(events.whereType<VoiceCredentialsReadyEvent>(), hasLength(1));

    await service.leaveVoiceChannel('guild-1');

    expect(gateway.updates.last.channelId, isNull);
    expect(clients.single.closed, isTrue);
  });

  test('does not send a voice state when DAVE is unavailable', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      nativeDaveService: null,
    )..setCurrentUserId('bot-1');
    addTearDown(service.close);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');

    expect(gateway.updates, isEmpty);
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _VoiceUpdate {
  const _VoiceUpdate({
    required this.guildId,
    required this.channelId,
    required this.selfMute,
    required this.selfDeaf,
  });

  final String guildId;
  final String? channelId;
  final bool selfMute;
  final bool selfDeaf;
}

final class _FakeMainGateway implements DiscordVoiceStateGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();
  final List<_VoiceUpdate> updates = [];

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  void dispatch(String name, Map<String, Object?> data) {
    _events.add(DiscordGatewayDispatch(name: name, data: data));
  }

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  }) {
    updates.add(
      _VoiceUpdate(
        guildId: guildId,
        channelId: channelId,
        selfMute: selfMute,
        selfDeaf: selfDeaf,
      ),
    );
  }
}

final class _FakeVoiceClient implements DiscordVoiceClient {
  _FakeVoiceClient(this.credentials);

  final VoiceServerCredentials credentials;
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  bool connected = false;
  bool closed = false;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}

final class _CapabilityOnlyDaveService implements VoiceDaveService {
  @override
  int get maxProtocolVersion => 1;

  @override
  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  }) => throw UnsupportedError('Not used by signaling boundary tests');
}
