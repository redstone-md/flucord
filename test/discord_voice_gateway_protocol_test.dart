import 'package:flucord/src/data/discord/discord_voice_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_voice_udp_transport.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DiscordVoiceGatewayProtocol protocol() => DiscordVoiceGatewayProtocol(
    credentials: _credentials,
    maxDaveProtocolVersion: 1,
  );

  Map<String, Object?> frame(int opcode, [Object? data]) => {
    'op': opcode,
    'd': data,
  };

  group('hello and the heartbeat watchdog', () {
    test('hello schedules the interval the server named', () {
      final actions = protocol()
          .accept(frame(DiscordVoiceGatewayOpcode.hello, {
            'heartbeat_interval': 13750,
          }));

      expect(
        (actions.single as DiscordVoiceGatewayScheduleHeartbeat).interval,
        const Duration(milliseconds: 13750),
      );
    });

    test('a hello without an interval decides nothing', () {
      expect(
        protocol()
            .accept(frame(DiscordVoiceGatewayOpcode.hello, <String, Object?>{})),
        isEmpty,
      );
      expect(
        protocol().accept(frame(DiscordVoiceGatewayOpcode.hello, null)),
        isEmpty,
      );
    });

    test('two unanswered heartbeats are tolerated, the third is not', () {
      final gateway = protocol();

      expect(gateway.heartbeatDue(), isA<DiscordVoiceGatewaySend>());
      expect(gateway.heartbeatDue(), isA<DiscordVoiceGatewaySend>());
      expect(gateway.heartbeatDue(), isA<DiscordVoiceGatewayReconnect>());
    });

    test('an acknowledgement settles the count', () {
      final gateway = protocol()..heartbeatDue()..heartbeatDue();
      gateway.accept(frame(DiscordVoiceGatewayOpcode.heartbeatAck, null));

      expect(gateway.heartbeatDue(), isA<DiscordVoiceGatewaySend>());
    });

    test('the heartbeat frame carries the acknowledged sequence', () {
      final gateway = protocol()
        ..accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData))
        ..acceptSequence(31);

      final send = gateway.heartbeatDue() as DiscordVoiceGatewaySend;

      expect(send.payload['op'], DiscordVoiceGatewayOpcode.heartbeat);
      expect((send.payload['d'] as Map)['seq_ack'], 31);
    });
  });

  group('close-code triage', () {
    test('codes Discord re-issues wait for new credentials instead of redialling',
        () {
      for (final code in [4006, 4014, 4022]) {
        expect(
          protocol().closedWithCode(code),
          isA<DiscordVoiceGatewayAwaitCredentials>(),
        );
      }
    });

    test('codes a redial cannot fix fail the connection', () {
      for (final code in [4004, 4009, 4011, 4017, 4020, 4021]) {
        expect(
          protocol().closedWithCode(code),
          isA<DiscordVoiceGatewayFail>(),
          reason: 'code $code',
        );
      }
    });

    test('anything else, including no code at all, reconnects', () {
      expect(protocol().closedWithCode(null), isA<DiscordVoiceGatewayReconnect>());
      expect(protocol().closedWithCode(1006), isA<DiscordVoiceGatewayReconnect>());
      expect(protocol().closedWithCode(4000), isA<DiscordVoiceGatewayReconnect>());
    });
  });

  group('resume eligibility', () {
    test('a fresh connection cannot resume, and neither can one still connecting',
        () {
      final gateway = protocol();

      expect(gateway.canResume, isFalse);
      gateway.accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData));
      expect(gateway.canResume, isFalse);
    });

    test('a session description makes the session resumable', () {
      final gateway = protocol()
        ..accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData))
        ..udpDiscovered(_discovery)
        ..accept(frame(DiscordVoiceGatewayOpcode.sessionDescription, _sessionData));

      expect(gateway.canResume, isTrue);
    });

    test('RESUMED makes the session resumable and reports ready', () {
      final actions = protocol()
          .accept(frame(DiscordVoiceGatewayOpcode.resumed, null));

      final dispatch = actions.single as DiscordVoiceGatewayDispatch;
      expect(
        (dispatch.event as VoiceSignalingStatusEvent).status,
        VoiceConnectionStatus.ready,
      );
    });

    test('a heartbeat timeout withdraws resume: the redial identifies afresh',
        () {
      final gateway = protocol()
        ..accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData))
        ..udpDiscovered(_discovery)
        ..accept(frame(DiscordVoiceGatewayOpcode.sessionDescription, _sessionData));
      expect(gateway.canResume, isTrue);

      gateway.heartbeatDue();
      gateway.heartbeatDue();
      final reconnect = gateway.heartbeatDue()
          as DiscordVoiceGatewayReconnect;

      expect(gateway.canResume, isFalse);
      expect(reconnect.error.toString(), contains('heartbeats'));
    });

    test('a revoked resume keeps the next connect identifying afresh', () {
      final gateway = protocol()..revokeResume();

      expect(gateway.canResume, isFalse);
    });
  });

  group('the identify to transport-ready handshake', () {
    test('a READY nobody can parse fails the connection', () {
      expect(
        protocol().accept(frame(DiscordVoiceGatewayOpcode.ready, <String, Object?>{})),
        [isA<DiscordVoiceGatewayFail>()],
      );
    });

    test('a READY without a supported mode fails the connection', () {
      final actions = protocol().accept(
        frame(DiscordVoiceGatewayOpcode.ready, {
          ..._readyData,
          'modes': ['xsalsa20_poly1305_lite'],
        }),
      );

      expect(actions.single, isA<DiscordVoiceGatewayFail>());
    });

    test('a READY asks the driver to discover UDP with the chosen mode', () {
      final actions = protocol()
          .accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData));

      final discover = actions.single as DiscordVoiceGatewayDiscoverUdp;

      expect(discover.ready.ssrc, 42);
      expect(discover.ready.ip, '198.51.100.4');
      expect(discover.ready.port, 50001);
      expect(discover.mode, 'aead_aes256_gcm_rtpsize');
    });

    test('a session description before the discovery has run fails', () {
      final gateway = protocol()
        ..accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData));

      expect(
        gateway.accept(
          frame(DiscordVoiceGatewayOpcode.sessionDescription, _sessionData),
        ).single,
        isA<DiscordVoiceGatewayFail>(),
      );
    });

    test('a description naming another mode or an oversized DAVE version fails',
        () {
      for (final description in [
        {..._sessionData, 'mode': 'xsalsa20_poly1305_lite'},
        {..._sessionData, 'dave_protocol_version': 2},
      ]) {
        final gateway = protocol()
          ..accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData))
          ..udpDiscovered(_discovery);

        expect(
          gateway.accept(
            frame(DiscordVoiceGatewayOpcode.sessionDescription, description),
          ).single,
          isA<DiscordVoiceGatewayFail>(),
          reason: 'description $description',
        );
      }
    });

    test('a completed handshake hands the driver a negotiated session', () {
      final gateway = protocol()
        ..accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData));
      final select = gateway
          .udpDiscovered(_discovery)
          .single as DiscordVoiceGatewaySend;

      expect(select.payload['op'], DiscordVoiceGatewayOpcode.selectProtocol);
      expect(
        (select.payload['d'] as Map)['data'],
        {
          'address': '203.0.113.7',
          'port': 50000,
          'mode': 'aead_aes256_gcm_rtpsize',
        },
      );
      // Without the codecs list the server carries the session as audio-only
      // and drops every picture, which is a stream that never loads.
      expect((select.payload['d'] as Map)['codecs'], [
        {'name': 'opus', 'type': 'audio', 'priority': 1000, 'payload_type': 120},
        {
          'name': 'H264',
          'type': 'video',
          'priority': 1000,
          'payload_type': 101,
          'rtx_payload_type': 102,
        },
      ]);

      final ready = gateway
          .accept(frame(DiscordVoiceGatewayOpcode.sessionDescription, _sessionData))
          .single as DiscordVoiceGatewayTransportReady;

      expect(ready.session.guildId, 'guild-1');
      expect(ready.session.ssrc, 42);
      expect(ready.session.address, '203.0.113.7');
      expect(ready.session.port, 50000);
      expect(ready.session.mode, 'aead_aes256_gcm_rtpsize');
      expect(ready.session.secretKey, List<int>.generate(32, (i) => i));
      expect(ready.session.daveProtocolVersion, 1);
      expect(gateway.session, same(ready.session));
      expect(gateway.audioSsrc, 42);
    });

    test('dropping the session keeps the identity for the redial', () {
      final gateway = protocol()
        ..accept(frame(DiscordVoiceGatewayOpcode.ready, _readyData))
        ..udpDiscovered(_discovery)
        ..accept(frame(DiscordVoiceGatewayOpcode.sessionDescription, _sessionData))
        ..accept(frame(DiscordVoiceGatewayOpcode.clientVideo, {
          'user_id': 'remote-2',
          'audio_ssrc': 91,
          'video_ssrc': 92,
        }))
        ..accept(frame(DiscordVoiceGatewayOpcode.speaking, {
          'user_id': 'remote-1',
          'ssrc': 77,
          'speaking': 1,
        }));

      gateway.dropSession();

      expect(gateway.session, isNull);
      expect(gateway.userIdForSsrc(77), isNull);
      // Kept: a resume does not re-announce cameras that did not change,
      // and dropping their owners would black out tiles still being sent.
      expect(gateway.userIdForVideoSsrc(92), 'remote-2');
      expect(gateway.canResume, isTrue);
      expect(gateway.audioSsrc, 42);
    });
  });

  group('the SSRC roster', () {
    test('speaking maps an SSRC to its user and dispatches the event', () {
      final actions = protocol().accept(
        frame(DiscordVoiceGatewayOpcode.speaking, {
          'user_id': 'remote-1',
          'ssrc': 77,
          'speaking': 3,
        }),
      );

      final event =
          (actions.single as DiscordVoiceGatewayDispatch).event
              as VoiceSpeakingEvent;

      expect(event.userId, 'remote-1');
      expect(event.speakingFlags, 3);
    });

    test('a speaking frame with impossible fields decides nothing', () {
      final gateway = protocol();

      expect(
        gateway.accept(frame(DiscordVoiceGatewayOpcode.speaking, {
          'user_id': 'remote-1',
          'ssrc': -1,
          'speaking': 1,
        })),
        isEmpty,
      );
      expect(
        gateway.accept(frame(DiscordVoiceGatewayOpcode.speaking, {
          'user_id': 5,
          'ssrc': 77,
          'speaking': 1,
        })),
        isEmpty,
      );
    });

    test('a peer video layout claims both SSRCs without a departure event', () {
      final gateway = protocol()
        ..accept(
          frame(DiscordVoiceGatewayOpcode.clientVideo, {
            'user_id': 'remote-2',
            'audio_ssrc': 91,
            'video_ssrc': 92,
          }),
        );

      expect(gateway.userIdForSsrc(91), 'remote-2');
      expect(gateway.userIdForVideoSsrc(92), 'remote-2');
      expect(gateway.session, isNull);
    });

    test('a departure drops the user from both rosters', () {
      final gateway = protocol()
        ..accept(frame(DiscordVoiceGatewayOpcode.clientVideo, {
          'user_id': 'remote-2',
          'audio_ssrc': 91,
          'video_ssrc': 92,
        }))
        ..accept(frame(DiscordVoiceGatewayOpcode.speaking, {
          'user_id': 'remote-1',
          'ssrc': 77,
          'speaking': 1,
        }));

      final actions = gateway.accept(
        frame(DiscordVoiceGatewayOpcode.clientDisconnect, {'user_id': 'remote-2'}),
      );

      expect(
        (actions.single as DiscordVoiceGatewayDispatch).event,
        isA<VoiceUserDisconnectedEvent>(),
      );
      expect(gateway.userIdForSsrc(91), isNull);
      expect(gateway.userIdForVideoSsrc(92), isNull);
      expect(gateway.userIdForSsrc(77), 'remote-1');
    });
  });
}

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'bot-1',
  sessionId: 'session-1',
  token: 'voice-token',
  endpoint: 'voice.example.test',
);

final _readyData = {
  'ssrc': 42,
  'ip': '198.51.100.4',
  'port': 50001,
  'modes': ['aead_aes256_gcm_rtpsize'],
};

const _discovery = DiscordVoiceIpDiscovery(
  address: '203.0.113.7',
  port: 50000,
);

final _sessionData = {
  'mode': 'aead_aes256_gcm_rtpsize',
  'secret_key': List<int>.generate(32, (index) => index),
  'dave_protocol_version': 1,
};
