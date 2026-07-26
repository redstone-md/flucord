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

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
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
    expect(gateway.updates.single.selfMute, isFalse);
    expect(clients, hasLength(1));
    expect(clients.single.connected, isTrue);
    expect(clients.single.credentials.sessionId, 'session-1');
    expect(events.whereType<VoiceCredentialsReadyEvent>(), hasLength(1));

    await service.joinVoiceChannel(
      guildId: 'guild-1',
      channelId: 'voice-1',
      selfMute: true,
    );
    await _flushEvents();

    expect(gateway.updates, hasLength(2));
    expect(gateway.updates.last.selfMute, isTrue);
    expect(clients, hasLength(1));

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

  test('emits documented participant voice state fields', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      nativeDaveService: _CapabilityOnlyDaveService(),
    )..setCurrentUserId('bot-1');
    final events = <VoiceSignalingEvent>[];
    final subscription = service.voiceEvents.listen(events.add);
    addTearDown(subscription.cancel);
    addTearDown(service.close);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
    gateway.dispatch('VOICE_STATE_UPDATE', {
      'guild_id': 'guild-1',
      'channel_id': 'voice-1',
      'user_id': 'member-1',
      'session_id': 'member-session',
      'self_mute': true,
      'self_deaf': false,
      'mute': false,
      'deaf': true,
      'self_stream': true,
      'self_video': true,
    });
    await _flushEvents();

    final participant = events.whereType<VoiceParticipantStateEvent>().single;
    expect(participant.userId, 'member-1');
    expect(participant.channelId, 'voice-1');
    expect(participant.selfMuted, isTrue);
    expect(participant.serverDeafened, isTrue);
    expect(participant.isStreaming, isTrue);
    expect(participant.isVideoEnabled, isTrue);
  });

  test('emits departure but ignores voice state from another guild', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      nativeDaveService: _CapabilityOnlyDaveService(),
    )..setCurrentUserId('bot-1');
    final events = <VoiceSignalingEvent>[];
    final subscription = service.voiceEvents.listen(events.add);
    addTearDown(subscription.cancel);
    addTearDown(service.close);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
    gateway.dispatch('VOICE_STATE_UPDATE', {
      'guild_id': 'guild-2',
      'channel_id': 'voice-2',
      'user_id': 'member-2',
    });
    gateway.dispatch('VOICE_STATE_UPDATE', {
      'guild_id': 'guild-1',
      'channel_id': null,
      'user_id': 'member-1',
      'self_mute': false,
      'self_deaf': false,
      'mute': false,
      'deaf': false,
    });
    await _flushEvents();

    final states = events.whereType<VoiceParticipantStateEvent>().toList();
    expect(states, hasLength(1));
    expect(states.single.userId, 'member-1');
    expect(states.single.channelId, isNull);
  });

  test('replays the occupants a channel already had on join', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      nativeDaveService: _CapabilityOnlyDaveService(),
    )..setCurrentUserId('bot-1');
    final events = <VoiceSignalingEvent>[];
    final subscription = service.voiceEvents.listen(events.add);
    addTearDown(subscription.cancel);
    addTearDown(service.close);

    // GUILD_CREATE lands at bootstrap, long before anyone presses join, and is
    // the only announcement of who is already sitting in the channel.
    gateway.dispatch('GUILD_CREATE', {
      'id': 'guild-1',
      'voice_states': [
        {'user_id': 'member-1', 'channel_id': 'voice-1', 'self_mute': true},
        {'user_id': 'member-2', 'channel_id': 'voice-2'},
      ],
    });
    await _flushEvents();
    expect(events.whereType<VoiceParticipantStateEvent>(), isEmpty);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
    await _flushEvents();

    final states = events.whereType<VoiceParticipantStateEvent>().toList();
    expect(states.map((state) => state.userId), ['member-1']);
    expect(states.single.selfMuted, isTrue);
  });

  test('pings the voice server when a voice socket reconnects', () async {
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
    addTearDown(service.close);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
    gateway.dispatch('VOICE_STATE_UPDATE', {
      'guild_id': 'guild-1',
      'channel_id': 'voice-1',
      'user_id': 'bot-1',
      'session_id': 'session-1',
    });
    gateway.dispatch('VOICE_SERVER_UPDATE', {
      'guild_id': 'guild-1',
      'token': 'voice-token',
      'endpoint': 'voice.example.test',
    });
    await _flushEvents();

    clients.single.emitStatus(VoiceConnectionStatus.reconnecting);
    await _flushEvents();
    expect(gateway.voiceServerPings, 1);

    // A ready transport is not a reason to poke the gateway.
    clients.single.emitStatus(VoiceConnectionStatus.ready);
    await _flushEvents();
    expect(gateway.voiceServerPings, 1);
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
  int voiceServerPings = 0;

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

  @override
  void pingVoiceServer() => voiceServerPings++;
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

  void emitStatus(VoiceConnectionStatus status) =>
      _events.add(VoiceSignalingStatusEvent(status));

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
  VoiceDaveEncryptor createEncryptor() =>
      throw UnsupportedError('Media encryption is outside this test');

  @override
  VoiceDaveDecryptor createDecryptor() =>
      throw UnsupportedError('Media decryption is outside this test');

  @override
  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  }) => throw UnsupportedError('Not used by signaling boundary tests');
}
