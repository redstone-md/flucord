import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_signaling_service.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';

void main() {
  test('refuses to join before Discord Gateway READY', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _UnusedSocketFactory(),
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
      socketFactory: _CallSocketFactory((credentials) {
        final client = _FakeVoiceClient(credentials);
        clients.add(client);
        return client;
      }),
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

  test('joins without DAVE, on the transport cipher alone', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,

      // An account with no native DAVE library. The join is not held hostage
      // to it; that the sockets this factory would dial identify with
      // max_dave_protocol_version 0 is the factory's own test.
      socketFactory: DiscordVoiceGatewaySocketFactory(),
    )..setCurrentUserId('bot-1');
    addTearDown(service.close);

    await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');

    expect(gateway.updates.single.channelId, 'voice-1');
  });

  test('emits documented participant voice state fields', () async {
    final gateway = _FakeMainGateway();
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _UnusedSocketFactory(),
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
      socketFactory: _UnusedSocketFactory(),
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
      socketFactory: _UnusedSocketFactory(),
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
      socketFactory: _CallSocketFactory((credentials) {
        final client = _FakeVoiceClient(credentials);
        clients.add(client);
        return client;
      }),
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

    await service.joinVoiceChannel(
      guildId: 'guild-1',
      channelId: 'voice-1',
      selfMute: true,
    );
    gateway.updates.clear();

    clients.single.emitStatus(VoiceConnectionStatus.reconnecting);
    await _flushEvents();
    expect(gateway.voiceServerPings, 1);

    // The channel is announced again as well. The ping asks Discord to
    // re-issue what it believes it already handed out; re-announcing is what
    // makes it hand out a new one, and a client holding credentials from a
    // replaced session otherwise waited for an update that never came.
    expect(gateway.updates.single.channelId, 'voice-1');
    // With the flags it was announced with. Opcode 4 is a whole-state frame,
    // so repeating it with the defaults would quietly unmute somebody in the
    // middle of a reconnect.
    expect(gateway.updates.single.selfMute, isTrue);

    // A ready transport is not a reason to poke the gateway.
    clients.single.emitStatus(VoiceConnectionStatus.ready);
    await _flushEvents();
    expect(gateway.voiceServerPings, 1);
  });

  test('forces a fresh pair when nothing re-issues the credentials', () async {
    final gateway = _FakeMainGateway();
    final clients = <_FakeVoiceClient>[];
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      reissueFallbackDelay: const Duration(milliseconds: 20),
      socketFactory: _CallSocketFactory((credentials) {
        final client = _FakeVoiceClient(credentials);
        clients.add(client);
        return client;
      }),
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
    gateway.updates.clear();

    // The ping and the re-announcement change nothing Discord can see, so
    // nothing answers them. Short of the fallback's wait, the cycle has not
    // fired yet.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // The leave and the rejoin: both halves of the voice state change, which
    // is the one ask Discord cannot answer with silence.
    expect(gateway.updates, hasLength(2));
    expect(gateway.updates.first.channelId, isNull);
    expect(gateway.updates.last.channelId, 'voice-1');
  });

  test('calls the cycle off after three unanswered rounds', () async {
    final gateway = _FakeMainGateway();
    final clients = <_FakeVoiceClient>[];
    final events = <VoiceSignalingEvent>[];
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      reissueFallbackDelay: const Duration(milliseconds: 10),
      socketFactory: _CallSocketFactory((credentials) {
        final client = _FakeVoiceClient(credentials);
        clients.add(client);
        return client;
      }),
    )..setCurrentUserId('bot-1');
    final subscription = service.voiceEvents.listen(events.add);
    addTearDown(subscription.cancel);
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
    // Every cycle goes unanswered: no fresh pair, no client to report a
    // status, so the timers keep firing until the cap stops them.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      gateway.updates.where((update) => update.channelId == null),
      hasLength(3),
    );
    final statuses = events.whereType<VoiceSignalingStatusEvent>().toList();
    expect(statuses.last.status, VoiceConnectionStatus.failure);
    expect(statuses.last.error.toString(), contains('refused'));
  });

  test('a join into the stuck channel forces the re-issue', () async {
    final gateway = _FakeMainGateway();
    final clients = <_FakeVoiceClient>[];
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _CallSocketFactory((credentials) {
        final client = _FakeVoiceClient(credentials);
        clients.add(client);
        return client;
      }),
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

    for (final status in [
      VoiceConnectionStatus.failure,
      VoiceConnectionStatus.disconnected,
    ]) {
      clients.single.emitStatus(status);
      await _flushEvents();
      gateway.updates.clear();

      await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');

      // An identical voice state is a no-op server-side; joining the same
      // channel on a dead session has to leave and rejoin instead.
      expect(gateway.updates, hasLength(2));
      expect(gateway.updates.first.channelId, isNull);
      expect(gateway.updates.last.channelId, 'voice-1');
    }
  });

  group('a press during a reconnect', () {
    /// A Participant in a room over the real service, with its socket up.
    Future<
      ({
        _FakeMainGateway gateway,
        _FakeVoiceClient client,
        VoiceController voice,
      })
    >
    joinedRoom({
      Duration reissueFallbackDelay = const Duration(seconds: 2),
    }) async {
      final gateway = _FakeMainGateway();
      final clients = <_FakeVoiceClient>[];
      final service = DiscordVoiceSignalingService(
        mainGateway: gateway,
        socketFactory: _CallSocketFactory((credentials) {
          final client = _FakeVoiceClient(credentials);
          clients.add(client);
          return client;
        }),
        reissueFallbackDelay: reissueFallbackDelay,
      )..setCurrentUserId('bot-1');
      addTearDown(service.close);
      final voice = VoiceController(
        const NoopVoiceMediaService(),
        signalingServiceProvider: () => service,
      );
      addTearDown(voice.dispose);

      await voice.connect(guildId: 'guild-1', channelId: 'voice-1');
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
      return (gateway: gateway, client: clients.single, voice: voice);
    }

    test('sends the voice state and no leave and join cycle', () async {
      final room = await joinedRoom();
      room.client.emitStatus(VoiceConnectionStatus.reconnecting);
      await _flushEvents();
      room.gateway.updates.clear();

      await room.voice.toggleMute();
      expect(room.gateway.updates.single.channelId, 'voice-1');
      expect(room.gateway.updates.single.selfMute, isTrue);
      room.gateway.updates.clear();

      await room.voice.toggleDeafen();
      expect(room.gateway.updates.single.channelId, 'voice-1');
      expect(room.gateway.updates.single.selfDeaf, isTrue);
      room.gateway.updates.clear();

      await room.voice.setCameraAnnounced(enabled: true);
      expect(room.gateway.updates.single.channelId, 'voice-1');
      expect(room.gateway.updates.single.selfVideo, isTrue);
    });

    test('is what a stalled reconnect rejoins with', () async {
      final room = await joinedRoom(
        reissueFallbackDelay: const Duration(milliseconds: 20),
      );
      room.client.emitStatus(VoiceConnectionStatus.reconnecting);
      await _flushEvents();

      await room.voice.toggleMute();
      room.gateway.updates.clear();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The recovery's own cycle, once its wait ran out.
      expect(room.gateway.updates.first.channelId, isNull);
      expect(room.gateway.updates[1].channelId, 'voice-1');
      expect(room.gateway.updates[1].selfMute, isTrue);
    });

    test('on a failed connection rejoins with the new choice', () async {
      final room = await joinedRoom();
      room.client.emitStatus(VoiceConnectionStatus.failure);
      await _flushEvents();
      room.gateway.updates.clear();

      await room.voice.toggleMute();

      expect(room.gateway.updates, hasLength(2));
      expect(room.gateway.updates.first.channelId, isNull);
      expect(room.gateway.updates.last.channelId, 'voice-1');
      expect(room.gateway.updates.last.selfMute, isTrue);
    });
  });

  test('carries video on the connection the call opened', () async {
    final gateway = _FakeMainGateway();
    final client = _FakeVoiceClient(
      const VoiceServerCredentials(
        guildId: 'guild-1',
        channelId: 'voice-1',
        userId: 'bot-1',
        sessionId: 'session-1',
        token: 'voice-token',
        endpoint: 'voice.example.test',
      ),
    );
    final service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _CallSocketFactory((credentials) => client),
    )..setCurrentUserId('bot-1');
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

    // The camera sends through the same doors a viewer's pictures arrive on,
    // with nothing between the controller and the connection.
    expect(service.activeVideoTransport, same(client));
    final frame = DiscordRtpFrame(
      header: DiscordRtpHeader(
        payloadType: DiscordRtpHeader.discordVideoPayloadType,
        sequence: 1,
        timestamp: 1,
        ssrc: 1,
      ),
      payload: Uint8List.fromList(const [1, 2, 3]),
    );
    service.sendVideoFrame(frame);
    expect(client.sentFrames, [frame]);

    final received = <(String, DiscordRtpFrame)>[];
    final subscription = service.remoteVideo.listen(received.add);
    addTearDown(subscription.cancel);
    client.emitVideo('member-1', frame);
    await _flushEvents();
    expect(received, [('member-1', frame)]);
  });

  group('credentials that overlap', () {
    /// A Participant who joined and is waiting for credentials. Each client
    /// the service builds lands in [clients], in the order it was built.
    Future<
      ({
        _FakeMainGateway gateway,
        DiscordVoiceSignalingService service,
        List<_FakeVoiceClient> clients,
        List<VoiceSignalingEvent> events,
      })
    >
    joinedCall({Completer<void>? firstConnect}) async {
      final gateway = _FakeMainGateway();
      final clients = <_FakeVoiceClient>[];
      final service = DiscordVoiceSignalingService(
        mainGateway: gateway,
        socketFactory: _CallSocketFactory((credentials) {
          final client = _FakeVoiceClient(
            credentials,
            connectGate: clients.isEmpty ? firstConnect : null,
          );
          clients.add(client);
          return client;
        }),
      )..setCurrentUserId('bot-1');
      addTearDown(service.close);
      final events = <VoiceSignalingEvent>[];
      final subscription = service.voiceEvents.listen(events.add);
      addTearDown(subscription.cancel);
      await service.joinVoiceChannel(guildId: 'guild-1', channelId: 'voice-1');
      return (
        gateway: gateway,
        service: service,
        clients: clients,
        events: events,
      );
    }

    /// One whole pair, the way the main gateway hands out a session.
    void sendCredentials(_FakeMainGateway gateway, {required String token}) {
      gateway.dispatch('VOICE_STATE_UPDATE', {
        'guild_id': 'guild-1',
        'channel_id': 'voice-1',
        'user_id': 'bot-1',
        'session_id': 'session-1',
      });
      gateway.dispatch('VOICE_SERVER_UPDATE', {
        'guild_id': 'guild-1',
        'token': token,
        'endpoint': 'voice.example.test',
      });
    }

    List<VoiceConnectionStatus> statuses(List<VoiceSignalingEvent> events) =>
        events
            .whereType<VoiceSignalingStatusEvent>()
            .map((event) => event.status)
            .toList();

    test('two in one batch leave one client, and it plays once', () async {
      final call = await joinedCall();
      sendCredentials(call.gateway, token: 'token-0');
      await _flushEvents();

      sendCredentials(call.gateway, token: 'token-1');
      sendCredentials(call.gateway, token: 'token-2');
      await _flushEvents();

      expect(
        call.clients.where((client) => !client.closed).map((c) => c.token),
        ['token-2'],
      );

      final heard = <VoiceRemoteOpusFrame>[];
      final subscription = call.service.remoteAudio.listen(heard.add);
      addTearDown(subscription.cancel);
      for (final client in call.clients) {
        client.emitAudio('member-1');
      }
      await _flushEvents();
      expect(heard, hasLength(1));
    });

    group('while the older client is still closing', () {
      /// Two more pairs arrive after a client is up, and its close is held.
      Future<
        ({
          DiscordVoiceSignalingService service,
          List<_FakeVoiceClient> clients,
          Completer<void> closing,
        })
      >
      overlapDuringClose() async {
        final call = await joinedCall();
        sendCredentials(call.gateway, token: 'token-0');
        await _flushEvents();
        final closing = Completer<void>();
        call.clients.single.closeGate = closing;

        sendCredentials(call.gateway, token: 'token-1');
        sendCredentials(call.gateway, token: 'token-2');
        await _flushEvents();
        return (service: call.service, clients: call.clients, closing: closing);
      }

      test('no newer client starts', () async {
        final call = await overlapDuringClose();

        expect(call.clients.single.token, 'token-0');

        call.closing.complete();
        await _flushEvents();

        expect(call.clients.map((client) => client.token), [
          'token-0',
          'token-2',
        ]);
      });

      test('the microphone ends up on the client that remains', () async {
        final call = await overlapDuringClose();
        call.closing.complete();
        await _flushEvents();

        final opus = Uint8List.fromList(const [1, 2, 3]);
        call.service.sendOpusFrame(opus);

        final remaining = call.clients.where((client) => !client.closed);
        expect(remaining.map((client) => client.token), ['token-2']);
        expect(remaining.single.sentOpus, [opus]);
      });
    });

    test('a close that throws does not stop the next client', () async {
      final call = await joinedCall();
      sendCredentials(call.gateway, token: 'token-0');
      await _flushEvents();
      final closing = Completer<void>();
      call.clients.single.closeGate = closing;

      sendCredentials(call.gateway, token: 'token-1');
      await _flushEvents();
      closing.completeError(StateError('the socket would not close'));
      await _flushEvents();
      sendCredentials(call.gateway, token: 'token-2');
      await _flushEvents();

      expect(call.clients.last.token, 'token-2');
      expect(call.clients.last.connected, isTrue);
    });

    test('after Leave, no client reports a status', () async {
      final call = await joinedCall();
      sendCredentials(call.gateway, token: 'token-0');
      await _flushEvents();
      sendCredentials(call.gateway, token: 'token-1');
      sendCredentials(call.gateway, token: 'token-2');
      await _flushEvents();

      await call.service.leaveVoiceChannel('guild-1');
      await _flushEvents();
      call.events.clear();
      for (final client in call.clients) {
        client.emitStatus(VoiceConnectionStatus.ready);
      }
      await _flushEvents();

      expect(statuses(call.events), isEmpty);
    });

    test('a dial that fails after Leave reports nothing', () async {
      final dial = Completer<void>();
      final call = await joinedCall(firstConnect: dial);
      sendCredentials(call.gateway, token: 'token-1');
      await _flushEvents();

      await call.service.leaveVoiceChannel('guild-1');
      await _flushEvents();
      call.events.clear();
      dial.completeError(StateError('the dial was dropped'));
      await _flushEvents();

      expect(statuses(call.events), isEmpty);
    });

    test('a dial that never returns does not hold up the newer client, and '
        'its late failure is not news', () async {
      final dial = Completer<void>();
      final call = await joinedCall(firstConnect: dial);
      sendCredentials(call.gateway, token: 'token-1');
      await _flushEvents();

      sendCredentials(call.gateway, token: 'token-2');
      await _flushEvents();
      expect(call.clients.map((client) => client.token), [
        'token-1',
        'token-2',
      ]);
      expect(call.clients.first.closed, isTrue);

      call.events.clear();
      dial.completeError(StateError('the dial was dropped'));
      await _flushEvents();

      expect(statuses(call.events), isEmpty);
    });
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
    required this.selfVideo,
  });

  final String guildId;
  final String? channelId;
  final bool selfMute;
  final bool selfDeaf;
  final bool selfVideo;
}

final class _FakeMainGateway implements DiscordVoiceStateGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();
  final List<_VoiceUpdate> updates = [];
  int voiceServerPings = 0;

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  String? get sessionId => 'session-1';

  void dispatch(String name, Map<String, Object?> data) {
    _events.add(DiscordGatewayDispatch(name: name, data: data));
  }

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) {
    updates.add(
      _VoiceUpdate(
        guildId: guildId,
        channelId: channelId,
        selfMute: selfMute,
        selfDeaf: selfDeaf,
        selfVideo: selfVideo,
      ),
    );
  }

  @override
  void pingVoiceServer() => voiceServerPings++;
}

/// Carries pictures the same way the production client does, so the video
/// half of the call's connection is testable without a socket.
final class _FakeVoiceClient
    implements DiscordVoiceClient, VoiceAudioTransport {
  _FakeVoiceClient(this.credentials, {this.connectGate});

  final VoiceServerCredentials credentials;
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();
  final StreamController<(String, DiscordRtpFrame)> _video =
      StreamController.broadcast();
  final StreamController<VoiceRemoteOpusFrame> _audio =
      StreamController.broadcast();
  final List<DiscordRtpFrame> sentFrames = [];
  final List<Uint8List> sentOpus = [];

  /// Holds [connect] open, the way a slow dial does.
  final Completer<void>? connectGate;

  /// Holds [close] open, the way a slow socket close does.
  Completer<void>? closeGate;
  bool connected = false;
  bool closed = false;

  String get token => credentials.token;

  @override
  int? get audioSsrc => null;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets => _video.stream;

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio => _audio.stream;

  @override
  void sendOpusFrame(Uint8List opusFrame) => sentOpus.add(opusFrame);

  @override
  void skipOpusFrame() {}

  @override
  Future<void> finishSpeaking() async {}

  /// A closed client is silent, as the real one is.
  void emitStatus(VoiceConnectionStatus status) {
    if (!_events.isClosed) _events.add(VoiceSignalingStatusEvent(status));
  }

  /// Delivers one frame of somebody's voice, if this client is still open.
  void emitAudio(String userId) {
    if (_audio.isClosed) return;
    _audio.add(
      VoiceRemoteOpusFrame(userId: userId, opus: Uint8List.fromList(const [9])),
    );
  }

  /// Delivers a picture as if it arrived off the wire.
  void emitVideo(String userId, DiscordRtpFrame frame) =>
      _video.add((userId, frame));

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) => false;

  @override
  int sendVideoFrame(DiscordRtpFrame frame) {
    sentFrames.add(frame);
    return frame.payload.length;
  }

  @override
  void sendMediaSinkWants({
    Map<int, int> perSsrc = const {},
    int? any,
    Map<int, double> pixelCounts = const {},
  }) {}

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) => frame;

  @override
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) => picture;

  @override
  Future<void> connect() async {
    connected = true;
    await connectGate?.future;
  }

  @override
  void sendPictureLoss({required int mediaSsrc}) {}

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
    await _video.close();
    await _audio.close();
    await closeGate?.future;
  }
}

/// The seam most of this file never reaches: joining and roster behaviour,
/// not the sockets a join would dial.
final class _UnusedSocketFactory implements DiscordVoiceSocketFactory {
  @override
  int get maxDaveProtocolVersion => 0;

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
  @override
  int get maxDaveProtocolVersion => 0;

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
