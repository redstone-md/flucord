import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/domain/stream_quality.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_voice_session_assembler.dart';
import 'package:flucord/src/data/discord/discord_voice_udp_transport.dart';
import 'package:flucord/src/data/discord/discord_voice_websocket.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_dave.dart';

part 'discord_voice_transport_handshake_cases.dart';

void main() {
  _handshakeCases();

  group('Discord Voice Gateway v8', () {
    test('a screen share declares the stream it carries', () {
      final protocol = DiscordVoiceGatewayProtocol(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        carriesVideo: true,
      );

      final identify = protocol.identify()['d']! as Map<String, Object?>;

      // Discord closes a Go Live socket that identifies without this with
      // `identifyRefused`, the moment it finishes connecting, which is
      // what every share and every attempt to watch somebody was doing.
      expect(identify['video'], isTrue);
      // A screen, not a camera. Discord closes a Go Live socket that says
      // "video" with `identifyRefused` the moment the handshake finishes.
      expect(identify['streams'], [
        {'type': 'screen', 'rid': '100', 'quality': 100},
      ]);
    });

    test('a call says it carries no video, and lists no streams', () {
      final protocol = DiscordVoiceGatewayProtocol(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
      );

      final identify = protocol.identify()['d']! as Map<String, Object?>;

      // A camera on a call is announced later, with opcode 12, on a socket
      // that was opened for audio.
      expect(identify['video'], isFalse);
      expect(identify.containsKey('streams'), isFalse);
    });

    test('builds identify, resume, heartbeat, and protocol payloads', () {
      final protocol = DiscordVoiceGatewayProtocol(
        credentials: _credentials,
        maxDaveProtocolVersion: 1,
      )..acceptSequence(19);

      expect(protocol.identify(), {
        'op': 0,
        'd': {
          'server_id': 'guild-1',
          'channel_id': 'voice-1',
          'user_id': 'bot-1',
          'session_id': 'session-1',
          'token': 'voice-token',
          'max_dave_protocol_version': 1,
          'video': false,
        },
      });
      expect(protocol.resume()['d'], {
        'server_id': 'guild-1',
        'session_id': 'session-1',
        'token': 'voice-token',
        'seq_ack': 19,
      });
      expect(protocol.heartbeat(123)['d'], {'t': 123, 'seq_ack': 19});
      expect(
        protocol.selectProtocol(
          address: '203.0.113.7',
          port: 50000,
          mode: 'aead_aes256_gcm_rtpsize',
        ),
        {
          'op': 1,
          'd': {
            'protocol': 'udp',
            'data': {
              'address': '203.0.113.7',
              'port': 50000,
              'mode': 'aead_aes256_gcm_rtpsize',
            },
            // The server carries a session without codecs as audio-only.
            'codecs': [
              {
                'name': 'opus',
                'type': 'audio',
                'priority': 1000,
                'payload_type': 120,
              },
              {
                'name': 'H264',
                'type': 'video',
                'priority': 1000,
                'payload_type': 101,
                'rtx_payload_type': 102,
              },
            ],
          },
        },
      );
    });

    test('dials the port the endpoint names', () async {
      // The endpoint's port is where the session lives: an endpoint naming
      // 2083, dialled on 443, was answered with `sessionInvalid` on every
      // attempt, while the one endpoint naming 443 was the one connection
      // that ever opened.
      const credentials = VoiceServerCredentials(
        guildId: 'guild-1',
        channelId: 'voice-1',
        userId: 'bot-1',
        sessionId: 'session-1',
        token: 'voice-token',
        endpoint: 'c-mad01-261e88f2.discord.media:2083',
      );
      final connector = _FakeVoiceSocketConnector(_FakeVoiceWebSocket());
      final client = DiscordVoiceGatewayClient(
        credentials: credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: connector,
        udpTransport: _FakeVoiceUdpTransport(),
      );
      addTearDown(client.close);

      await client.connect();

      expect(
        connector.lastUri.toString(),
        'wss://c-mad01-261e88f2.discord.media:2083?v=8',
      );
    });

    test('a sink wants ask reaches the socket as opcode 15', () async {
      final socket = _FakeVoiceWebSocket();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: _FakeVoiceSocketConnector(socket),
        udpTransport: _FakeVoiceUdpTransport(),
      );
      addTearDown(client.close);

      await client.connect();
      // The identify went out on connect, so this is the frame after it.
      expect(_jsonAt(socket.sent, 0)['op'], 0);
      client.sendMediaSinkWants(any: 100, perSsrc: {8964: 50});

      // The wiring, not just the payload: a method that built the right map
      // and dropped it on the floor would pass every protocol test and still
      // leave a viewer watching a black rectangle.
      expect(socket.sent, hasLength(2));
      expect(socket.sent.last, isA<String>());
      expect(_jsonAt(socket.sent, 1), {
        'op': 15,
        'd': {'8964': 50, 'any': 100},
      });
    });

    test(
      'feedback and keepalives never count against the key',
      () async {
        final socket = _FakeVoiceWebSocket();
        final udp = _FakeVoiceUdpTransport();
        final client = DiscordVoiceGatewayClient(
          credentials: _credentials,
          maxDaveProtocolVersion: 1,
          socketConnector: _FakeVoiceSocketConnector(socket),
          udpTransport: udp,
        );
        final statuses = <VoiceSignalingStatusEvent>[];
        final subscription = client.events.listen((event) {
          if (event is VoiceSignalingStatusEvent) statuses.add(event);
        });
        addTearDown(subscription.cancel);
        addTearDown(client.close);

        await client.connect();
        socket.addJson({
          'op': 2,
          'd': {
            'ssrc': 42,
            'ip': '127.0.0.1',
            'port': 5000,
            'modes': ['aead_aes256_gcm_rtpsize'],
          },
        });
        await _flushEvents();
        socket.addJson({
          'op': 4,
          'd': {
            'mode': 'aead_aes256_gcm_rtpsize',
            'secret_key': List<int>.generate(32, (index) => index),
            'dave_protocol_version': 0,
          },
        });
        await _flushEvents();
        expect(
          statuses.last.status,
          VoiceConnectionStatus.ready,
        );

        // A send-only socket receives no media, only what a sender's pictures
        // generate: receiver reports (packet types 192-223) and the
        // eight-byte keepalives. None of it can authenticate, and none of it
        // ever said the key was wrong.
        final receiverReport = Uint8List(64);
        receiverReport[0] = 0x80;
        receiverReport[1] = 201;
        final keepalive = Uint8List(8);
        for (var i = 0; i < 60; i++) {
          udp.addPacket(i.isEven ? receiverReport : keepalive);
        }
        await _flushEvents();

        expect(
          statuses.where(
            (status) => status.status == VoiceConnectionStatus.reconnecting,
          ),
          isEmpty,
        );

        // And genuine media still comes through after the storm.
        final receivedFrame = client.audioPackets.first;
        final frame = DiscordRtpFrame(
          header: DiscordRtpHeader(sequence: 3, timestamp: 4, ssrc: 42),
          payload: [9, 9, 9],
        );
        client.sendAudioFrame(frame);
        udp.addPacket(udp.sentPackets.last);
        expect((await receivedFrame).payload, frame.payload);
      },
    );

    test(
      'a picture-loss indication becomes a keyframe request, once per burst',
      () async {
        final socket = _FakeVoiceWebSocket();
        final udp = _FakeVoiceUdpTransport();
        final client = DiscordVoiceGatewayClient(
          credentials: _credentials,
          maxDaveProtocolVersion: 1,
          socketConnector: _FakeVoiceSocketConnector(socket),
          udpTransport: udp,
        );
        final keyframeRequests = <VoiceKeyframeRequestedEvent>[];
        final subscription = client.events.listen((event) {
          if (event is VoiceKeyframeRequestedEvent) keyframeRequests.add(event);
        });
        addTearDown(subscription.cancel);
        // The packet chain only runs while something reads it, and a test
        // that only watches the events stream would never deliver a packet.
        final mediaSubscription = client.audioPackets.listen((_) {});
        addTearDown(mediaSubscription.cancel);
        addTearDown(client.close);

        await client.connect();
        socket.addJson({
          'op': 2,
          'd': {
            'ssrc': 42,
            'ip': '127.0.0.1',
            'port': 5000,
            'modes': ['aead_aes256_gcm_rtpsize'],
          },
        });
        await _flushEvents();
        socket.addJson({
          'op': 4,
          'd': {
            'mode': 'aead_aes256_gcm_rtpsize',
            'secret_key': List<int>.generate(32, (index) => index),
            'dave_protocol_version': 0,
          },
        });
        await _flushEvents();

        // A viewer who cannot decode asks for a picture that stands alone.
        // One request leaves the socket even when several viewers asked at
        // once: a keyframe burst would cost more than the loss did.
        final pictureLoss = Uint8List(12);
        pictureLoss[0] = 0x81; // V=2, FMT=1 (PLI)
        pictureLoss[1] = 206; // payload-specific feedback
        udp.addPacket(pictureLoss);
        udp.addPacket(pictureLoss);
        await _flushEvents();
        expect(keyframeRequests, hasLength(1));

        // Other feedback is not a keyframe request.
        final receiverReport = Uint8List(64);
        receiverReport[0] = 0x80;
        receiverReport[1] = 201;
        udp.addPacket(receiverReport);
        await _flushEvents();
        expect(keyframeRequests, hasLength(1));
      },
    );

    test('reaches transport ready and routes DAVE binary frames', () async {
      final socket = _FakeVoiceWebSocket();
      final connector = _FakeVoiceSocketConnector(socket);
      final udp = _FakeVoiceUdpTransport();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 1,
        socketConnector: connector,
        udpTransport: udp,
      );
      final events = <VoiceSignalingEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(client.close);

      await client.connect();
      // Port 443 explicitly: an endpoint that names no port has none after
      // parsing, and `replace` keeping that dialled port 0 once, which the
      // server answered with a 522.
      expect(connector.lastUri.toString(), 'wss://voice.example.test:443?v=8');
      expect(_jsonAt(socket.sent, 0)['op'], 0);

      socket.addJson({
        'op': 2,
        'seq': 10,
        'd': {
          'ssrc': 42,
          'ip': '198.51.100.4',
          'port': 50001,
          'modes': ['aead_aes256_gcm_rtpsize'],
        },
      });
      await _flushEvents();

      expect(udp.discoveredHost, '198.51.100.4');
      expect(udp.discoveredPort, 50001);
      expect(_jsonAt(socket.sent, 1)['op'], 1);

      socket.addJson({
        'op': 4,
        'seq': 11,
        'd': {
          'mode': 'aead_aes256_gcm_rtpsize',
          'secret_key': List<int>.generate(32, (index) => index),
          'dave_protocol_version': 0,
        },
      });
      socket.addBinary([0, 12, 25, 7, 8, 9]);
      await _flushEvents();

      final ready = events.whereType<VoiceTransportReadyEvent>().single;
      expect(ready.session.address, '203.0.113.7');
      expect(ready.session.port, 50000);
      expect(ready.session.ssrc, 42);
      final dave = events.whereType<VoiceDaveBinaryEvent>().single;
      expect(dave.sequence, 12);
      expect(dave.opcode, 25);
      expect(dave.payload, [7, 8, 9]);

      final receivedFrame = client.audioPackets.first;
      final frame = DiscordRtpFrame(
        header: DiscordRtpHeader(sequence: 1, timestamp: 2, ssrc: 42),
        payload: [3, 4, 5],
      );
      expect(client.sendAudioFrame(frame), greaterThan(frame.payload.length));
      udp.addPacket(udp.sentPackets.single);
      expect((await receivedFrame).payload, frame.payload);

      socket.addJson({
        'op': 5,
        'seq': 13,
        'd': {'user_id': 'remote-1', 'ssrc': 77, 'speaking': 1},
      });
      await _flushEvents();

      final speaking = events.whereType<VoiceSpeakingEvent>().single;
      expect(speaking.userId, 'remote-1');
      expect(speaking.isSpeaking, isTrue);
      expect(client.userIdForSsrc(77), 'remote-1');

      // Opcode 12 is the peer's media layout. It must map their audio SSRC and
      // must not be mistaken for a departure.
      socket.addJson({
        'op': 12,
        'seq': 14,
        'd': {'user_id': 'remote-2', 'audio_ssrc': 91, 'video_ssrc': 92},
      });
      await _flushEvents();

      expect(client.userIdForSsrc(91), 'remote-2');
      expect(events.whereType<VoiceUserDisconnectedEvent>(), isEmpty);

      final remoteAudio = client.remoteAudio.first;
      final remoteAudioFrame = DiscordRtpFrame(
        header: DiscordRtpHeader(sequence: 2, timestamp: 3, ssrc: 91),
        payload: const [6, 7, 8],
      );
      client.sendAudioFrame(remoteAudioFrame);
      udp.addPacket(udp.sentPackets.last);
      final decodedAudio = await remoteAudio;
      expect(decodedAudio.userId, 'remote-2');
      expect(decodedAudio.opus, [6, 7, 8]);

      socket.addJson({
        'op': 13,
        'seq': 15,
        'd': {'user_id': 'remote-1'},
      });
      await _flushEvents();

      expect(client.userIdForSsrc(77), isNull);
      expect(client.userIdForSsrc(91), 'remote-2');
      expect(events.whereType<VoiceUserDisconnectedEvent>(), hasLength(1));

      client.sendDaveMessage(opcode: 26, payload: [3, 2, 1]);
      expect(socket.sent.last, isA<Uint8List>());
      expect(socket.sent.last, [26, 3, 2, 1]);
    });

    test('a packet that will not authenticate is dropped, not fatal', () async {
      final socket = _FakeVoiceWebSocket();
      final udp = _FakeVoiceUdpTransport();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: _FakeVoiceSocketConnector(socket),
        udpTransport: udp,
      );
      final events = <VoiceSignalingEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      addTearDown(client.close);
      await client.connect();
      socket.addJson({
        'op': 2,
        'seq': 1,
        'd': {
          'ssrc': 42,
          'ip': '198.51.100.4',
          'port': 50001,
          'modes': ['aead_aes256_gcm_rtpsize'],
        },
      });
      await _flushEvents();
      socket.addJson({
        'op': 4,
        'seq': 2,
        'd': {
          'mode': 'aead_aes256_gcm_rtpsize',
          'secret_key': List<int>.generate(32, (index) => index),
          'dave_protocol_version': 0,
        },
      });
      await _flushEvents();

      final received = <DiscordRtpFrame>[];
      final packets = client.audioPackets.listen(received.add);
      addTearDown(packets.cancel);

      // The same port carries RTCP, packets from before a key rotation, and
      // whatever else the network delivers. One of those used to travel out
      // as an exception and end the call.
      udp.addPacket(Uint8List.fromList(List<int>.filled(40, 7)));
      await _flushEvents();

      expect(received, isEmpty);
      expect(
        events.whereType<VoiceSignalingStatusEvent>().where(
          (event) => event.status == VoiceConnectionStatus.failure,
        ),
        isEmpty,
      );

      // A real one still arrives afterwards: the stream was not torn down.
      final frame = DiscordRtpFrame(
        header: DiscordRtpHeader(sequence: 1, timestamp: 2, ssrc: 42),
        payload: const [3, 4, 5],
      );
      client.sendAudioFrame(frame);
      udp.addPacket(udp.sentPackets.last);
      await _flushEvents();
      expect(received.single.payload, [3, 4, 5]);
    });

    test(
      'nothing decrypting at all is reported rather than passed over',
      () async {
        final socket = _FakeVoiceWebSocket();
        final udp = _FakeVoiceUdpTransport();
        final client = DiscordVoiceGatewayClient(
          credentials: _credentials,
          maxDaveProtocolVersion: 0,
          socketConnector: _FakeVoiceSocketConnector(socket),
          udpTransport: udp,
        );
        final events = <VoiceSignalingEvent>[];
        final subscription = client.events.listen(events.add);
        addTearDown(subscription.cancel);
        addTearDown(client.close);
        await client.connect();
        socket.addJson({
          'op': 2,
          'seq': 1,
          'd': {
            'ssrc': 42,
            'ip': '198.51.100.4',
            'port': 50001,
            'modes': ['aead_aes256_gcm_rtpsize'],
          },
        });
        await _flushEvents();
        socket.addJson({
          'op': 4,
          'seq': 2,
          'd': {
            'mode': 'aead_aes256_gcm_rtpsize',
            'secret_key': List<int>.generate(32, (index) => index),
            'dave_protocol_version': 0,
          },
        });
        await _flushEvents();
        final packets = client.audioPackets.listen((_) {});
        addTearDown(packets.cancel);

        // Fifty in a row with none succeeding is the key or the mode, not a
        // stray packet, and staying quiet about it would leave a silent call
        // looking healthy.
        for (var index = 0; index < 50; index++) {
          udp.addPacket(Uint8List.fromList(List<int>.filled(40, 7)));
        }
        await _flushEvents();

        // Asked to be re-issued rather than declared broken: a key that
        // decrypts nothing is a key from a session Discord has replaced, and
        // failing here dropped somebody out of a channel Discord still had
        // them in.
        expect(
          events.whereType<VoiceSignalingStatusEvent>().last.status,
          VoiceConnectionStatus.reconnecting,
        );
        expect(
          events.whereType<VoiceSignalingStatusEvent>().last.error.toString(),
          contains('none succeeded'),
        );
      },
    );

    test(
      'a payload type nobody claimed is not fed to the Opus decoder',
      () async {
        final socket = _FakeVoiceWebSocket();
        final udp = _FakeVoiceUdpTransport();
        final client = DiscordVoiceGatewayClient(
          credentials: _credentials,
          maxDaveProtocolVersion: 0,
          socketConnector: _FakeVoiceSocketConnector(socket),
          udpTransport: udp,
        );
        addTearDown(client.close);
        final audio = <DiscordRtpFrame>[];
        final subscription = client.audioPackets.listen(audio.add);
        addTearDown(subscription.cancel);

        await client.connect();
        socket.addJson({
          'op': 2,
          'd': {
            'ssrc': 11,
            'ip': '127.0.0.1',
            'port': 5000,
            'modes': ['aead_aes256_gcm_rtpsize'],
          },
        });
        socket.addJson({
          'op': 4,
          'd': {
            'mode': 'aead_aes256_gcm_rtpsize',
            'secret_key': List<int>.generate(32, (index) => index),
            'dave_protocol_version': 0,
          },
        });
        await _flushEvents();

        // Discord's own clients send pictures on several payload types. The
        // split used to be "anything that is not our own video type is audio",
        // so every one of those landed in the Opus path — and on a DAVE call
        // failed there, putting "DAVE decryption failed" over a working room.
        final picture = DiscordRtpFrame(
          header: DiscordRtpHeader(
            payloadType: 103,
            sequence: 1,
            timestamp: 2,
            ssrc: 12,
          ),
          payload: const [3, 4, 5],
        );
        client.sendAudioFrame(picture);
        udp.addPacket(udp.sentPackets.last);
        await _flushEvents();

        expect(audio, isEmpty);
      },
    );

    test('splits cameras from audio and attributes them by SSRC', () async {
      final socket = _FakeVoiceWebSocket();
      final udp = _FakeVoiceUdpTransport();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: _FakeVoiceSocketConnector(socket),
        udpTransport: udp,
      );
      addTearDown(client.close);
      await client.connect();
      socket.addJson({
        'op': 2,
        'seq': 1,
        'd': {
          'ssrc': 42,
          'ip': '198.51.100.4',
          'port': 50001,
          'modes': ['aead_aes256_gcm_rtpsize'],
        },
      });
      await _flushEvents();
      socket.addJson({
        'op': 4,
        'seq': 2,
        'd': {
          'mode': 'aead_aes256_gcm_rtpsize',
          'secret_key': List<int>.generate(32, (index) => index),
          'dave_protocol_version': 0,
        },
      });
      await _flushEvents();

      // The peer says which SSRC its pictures will arrive on.
      socket.addJson({
        'op': 12,
        'seq': 3,
        'd': {'user_id': 'remote-2', 'audio_ssrc': 91, 'video_ssrc': 92},
      });
      await _flushEvents();
      expect(client.userIdForVideoSsrc(92), 'remote-2');
      // The session the pictures will be attributed within.
      expect(client.session?.ssrc, 42);

      final audio = <DiscordRtpFrame>[];
      final video = <(String, DiscordRtpFrame)>[];
      final audioSubscription = client.audioPackets.listen(audio.add);
      final videoSubscription = client.videoPackets.listen(video.add);
      addTearDown(audioSubscription.cancel);
      addTearDown(videoSubscription.cancel);

      for (final frame in [
        // Opus on the voice payload type, a camera on the video one, and a
        // camera from somebody whose opcode 12 has not arrived.
        DiscordRtpFrame(
          header: DiscordRtpHeader(sequence: 1, timestamp: 2, ssrc: 42),
          payload: const [1, 2, 3],
        ),
        DiscordRtpFrame(
          header: DiscordRtpHeader(
            sequence: 2,
            timestamp: 3,
            ssrc: 92,
            payloadType: DiscordRtpHeader.discordVideoPayloadType,
          ),
          payload: const [4, 5, 6],
        ),
        DiscordRtpFrame(
          header: DiscordRtpHeader(
            sequence: 3,
            timestamp: 4,
            ssrc: 500,
            payloadType: DiscordRtpHeader.discordVideoPayloadType,
          ),
          payload: const [7, 8, 9],
        ),
      ]) {
        client.sendAudioFrame(frame);
        udp.addPacket(udp.sentPackets.last);
      }
      await _flushEvents();

      expect(audio.single.payload, [1, 2, 3]);
      // Attributed to whoever announced the SSRC; the unclaimed one is
      // dropped rather than drawn over somebody else's tile.
      expect(video.single.$1, 'remote-2');
      expect(video.single.$2.payload, [4, 5, 6]);

      socket.addJson({
        'op': 13,
        'seq': 4,
        'd': {'user_id': 'remote-2'},
      });
      await _flushEvents();
      expect(client.userIdForVideoSsrc(92), isNull);
    });

    test(
      'a socket drop that will resume keeps the media plane alive',
      () async {
        final socket = _FakeVoiceWebSocket();
        final udp = _FakeVoiceUdpTransport();
        final client = DiscordVoiceGatewayClient(
          credentials: _credentials,
          maxDaveProtocolVersion: 0,
          socketConnector: _FakeVoiceSocketConnector(socket),
          udpTransport: udp,
        );
        addTearDown(client.close);

        await client.connect();
        socket.addJson({
          'op': 2,
          'd': {
            'ssrc': 42,
            'ip': '127.0.0.1',
            'port': 5000,
            'modes': ['aead_aes256_gcm_rtpsize'],
          },
        });
        await _flushEvents();
        socket.addJson({
          'op': 4,
          'd': {
            'mode': 'aead_aes256_gcm_rtpsize',
            'secret_key': List<int>.generate(32, (index) => index),
            'dave_protocol_version': 0,
          },
        });
        await _flushEvents();

        await socket.closeFromServer(1006);
        await _flushEvents();

        // The socket is what dropped, not the session: UDP carries the same
        // key to the same media server, and a resume continues it. Throwing
        // the cipher away here left a share sending nothing at all, because
        // a RESUMED brings no second session description to build it from.
        final frame = DiscordRtpFrame(
          header: DiscordRtpHeader(sequence: 7, timestamp: 8, ssrc: 42),
          payload: [1, 2, 3],
        );
        expect(client.sendAudioFrame(frame), greaterThan(0));
      },
    );

    test('treats close code 4017 as terminal', () async {
      final socket = _FakeVoiceWebSocket();
      final connector = _FakeVoiceSocketConnector(socket);
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: connector,
        udpTransport: _FakeVoiceUdpTransport(),
      );
      final statuses = <VoiceSignalingStatusEvent>[];
      final subscription = client.events.listen((event) {
        if (event is VoiceSignalingStatusEvent) statuses.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(client.close);

      await client.connect();
      await socket.closeFromServer(4017);
      await _flushEvents();

      expect(connector.connectCount, 1);
      expect(statuses.last.status, VoiceConnectionStatus.failure);
      expect(statuses.last.error.toString(), contains('4017'));
    });

    test('one unanswered heartbeat does not end the call', () async {
      final socket = _FakeVoiceWebSocket();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: _FakeVoiceSocketConnector(socket),
        udpTransport: _FakeVoiceUdpTransport(),
      );
      final statuses = <VoiceSignalingStatusEvent>[];
      final subscription = client.events.listen((event) {
        if (event is VoiceSignalingStatusEvent) statuses.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(client.close);

      await client.connect();
      socket.addJson({
        'op': 8,
        'd': {'heartbeat_interval': 60},
      });
      await _flushEvents();
      // Two intervals with nothing coming back. An acknowledgement that lands
      // a moment after the next one is a slow network, not a dead socket —
      // and tearing the connection down for it was the first link in a chain
      // that had the call reconnecting for its whole life.
      await Future<void>.delayed(const Duration(milliseconds: 130));

      expect(
        statuses.where(
          (status) => status.status == VoiceConnectionStatus.reconnecting,
        ),
        isEmpty,
      );

      await Future<void>.delayed(const Duration(milliseconds: 130));

      expect(statuses.last.status, VoiceConnectionStatus.reconnecting);
      expect(statuses.last.error.toString(), contains('heartbeat'));
    });

    test('a session Discord ended waits to be handed a new one', () async {
      final socket = _FakeVoiceWebSocket();
      final connector = _FakeVoiceSocketConnector(socket);
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: connector,
        udpTransport: _FakeVoiceUdpTransport(),
      );
      final statuses = <VoiceSignalingStatusEvent>[];
      final subscription = client.events.listen((event) {
        if (event is VoiceSignalingStatusEvent) statuses.add(event);
      });
      addTearDown(subscription.cancel);
      addTearDown(client.close);

      await client.connect();
      await socket.closeFromServer(4014);
      await _flushEvents();

      // A `serverMoved` close is not a failure to show somebody. The token
      // that endpoint was reached with is dead, so redialling it would
      // fail; the main gateway answers a ping with a fresh
      // VOICE_SERVER_UPDATE and the connection is rebuilt from that.
      expect(statuses.last.status, VoiceConnectionStatus.reconnecting);
      expect(connector.connectCount, 1);
    });

    test(
      'a session Discord ended does not redial on unanswered heartbeats',
      () async {
        final socket = _FakeVoiceWebSocket();
        final connector = _FakeVoiceSocketConnector(socket);
        final client = DiscordVoiceGatewayClient(
          credentials: _credentials,
          maxDaveProtocolVersion: 0,
          socketConnector: connector,
          udpTransport: _FakeVoiceUdpTransport(),
        );
        addTearDown(client.close);

        await client.connect();
        socket.addJson({
          'op': 8,
          'd': {'heartbeat_interval': 60},
        });
        await _flushEvents();
        await socket.closeFromServer(4006);
        await _flushEvents();

        // The heartbeat timer keeps its interval against a socket that can
        // deliver no acknowledgement, and its watchdog used to redial the
        // dead token the protocol had just decided not to redial.
        await Future<void>.delayed(const Duration(milliseconds: 260));

        expect(connector.connectCount, 1);
        expect(
          socket.sent.where((frame) => jsonDecode(frame as String)['op'] == 0),
          hasLength(1),
        );
      },
    );

    test(
      'a socket that died under a send reconnects instead of throwing',
      () async {
        final socket = _FakeVoiceWebSocket();
        final client = DiscordVoiceGatewayClient(
          credentials: _credentials,
          maxDaveProtocolVersion: 0,
          socketConnector: _FakeVoiceSocketConnector(socket),
          udpTransport: _FakeVoiceUdpTransport(),
        );
        final statuses = <VoiceSignalingStatusEvent>[];
        final subscription = client.events.listen((event) {
          if (event is VoiceSignalingStatusEvent) statuses.add(event);
        });
        addTearDown(subscription.cancel);
        addTearDown(client.close);

        await client.connect();
        socket.addJson({
          'op': 2,
          'd': {
            'ssrc': 42,
            'ip': '127.0.0.1',
            'port': 5000,
            'modes': ['aead_aes256_gcm_rtpsize'],
          },
        });
        await _flushEvents();
        socket.failSends = true;

        // The crash this was found in: a socket closes between the last thing
        // read from it and the next write, and turning a camera on threw from
        // inside the button's callback and took the client down.
        expect(
          client.announceVideo(enabled: true, settings: _cameraProfile),
          isTrue,
        );
        await _flushEvents();

        expect(statuses.last.status, VoiceConnectionStatus.reconnecting);
        expect(
          statuses.last.error.toString(),
          contains('StreamSink is closed'),
        );
      },
    );

    test('routes DAVE gateway frames through the native boundary', () async {
      final socket = _FakeVoiceWebSocket();
      final daveService = _GatewayFakeDaveService();
      final client = DiscordVoiceGatewayClient(
        credentials: _credentials,
        maxDaveProtocolVersion: 1,
        daveService: daveService,
        socketConnector: _FakeVoiceSocketConnector(socket),
        udpTransport: _FakeVoiceUdpTransport(),
      );
      addTearDown(client.close);

      await client.connect();
      socket.addJson({
        'op': 2,
        'd': {
          'ssrc': 42,
          'ip': '127.0.0.1',
          'port': 5000,
          'modes': ['aead_aes256_gcm_rtpsize'],
        },
      });
      await _flushEvents();
      socket.addJson({
        'op': 4,
        'd': {
          'mode': 'aead_aes256_gcm_rtpsize',
          'secret_key': List<int>.generate(32, (index) => index),
          'dave_protocol_version': 1,
        },
      });
      await _flushEvents();

      // The description named DAVE v1, so the key package went out at once:
      // the server builds the group from the packages it holds when the
      // first commit is made, and a package waiting for the external sender
      // arrives after the group this account should be in.
      expect(socket.sent.last, [26, 9, 8]);

      socket.addBinary([0, 1, 25, 4, 5, 6]);
      await _flushEvents();

      expect(daveService.session?.externalSender, [4, 5, 6]);

      socket.addBinary([0, 2, 29, 0, 7, 3, 2, 1]);
      await _flushEvents();

      expect(daveService.session?.commit, [3, 2, 1]);
      expect(_jsonAt(socket.sent, socket.sent.length - 1), {
        'op': 23,
        'd': {'transition_id': 7},
      });
    });
  });
}

(String, Map<String, Object?>) _voiceState() => (
  'VOICE_STATE_UPDATE',
  {
    'guild_id': 'guild-1',
    'channel_id': 'voice-1',
    'user_id': 'bot-1',
    'session_id': 'session-1',
  },
);

(String, Map<String, Object?>) _voiceServer() => (
  'VOICE_SERVER_UPDATE',
  {
    'guild_id': 'guild-1',
    'token': 'voice-token',
    'endpoint': 'voice.example.test',
  },
);

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'bot-1',
  sessionId: 'session-1',
  token: 'voice-token',
  endpoint: 'voice.example.test',
);

/// The camera profile as announce payload: the announce path is under test,
/// so any settings answer, and the bitrate comes from the quality home rather
/// than being named again here.
const _cameraProfile = VideoEncoderSettings.camera(
  bitrate: StreamQualitySettings.defaultCameraBitrate,
);

Map<String, Object?> _jsonAt(List<Object> values, int index) =>
    (jsonDecode(values[index] as String) as Map).cast<String, Object?>();

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _FakeVoiceSocketConnector implements DiscordVoiceSocketConnector {
  _FakeVoiceSocketConnector(this.socket);

  final _FakeVoiceWebSocket socket;
  int connectCount = 0;
  Uri? lastUri;

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async {
    connectCount++;
    lastUri = uri;
    return socket;
  }
}

final class _FakeVoiceWebSocket implements DiscordVoiceWebSocket {
  final StreamController<Object?> _messages = StreamController.broadcast();
  final List<Object> sent = [];
  bool _closed = false;

  @override
  int? closeCode;

  @override
  Stream<Object?> get messages => _messages.stream;

  void addJson(Map<String, Object?> payload) =>
      _messages.add(jsonEncode(payload));

  void addBinary(List<int> payload) =>
      _messages.add(Uint8List.fromList(payload));

  Future<void> closeFromServer(int code) async {
    closeCode = code;
    await _closeMessages();
  }

  /// Set when the socket should behave like one that has closed underneath
  /// the client: `dart:io` throws "StreamSink is closed" on a write.
  bool failSends = false;

  @override
  void send(Object data) {
    if (failSends) throw StateError('StreamSink is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCode ??= code;
    await _closeMessages();
  }

  Future<void> _closeMessages() async {
    if (_closed) return;
    _closed = true;
    await _messages.close();
  }
}

final class _FakeVoiceUdpTransport implements DiscordVoiceUdpTransport {
  final StreamController<Uint8List> _packets = StreamController.broadcast();
  final List<Uint8List> sentPackets = [];
  String? discoveredHost;
  int? discoveredPort;
  bool _closed = false;

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  }) async {
    discoveredHost = host;
    discoveredPort = port;
    return const DiscordVoiceIpDiscovery(address: '203.0.113.7', port: 50000);
  }

  @override
  int send(Uint8List packet) {
    sentPackets.add(packet);
    return packet.length;
  }

  void addPacket(Uint8List packet) => _packets.add(packet);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _packets.close();
  }
}

final class _GatewayFakeDaveService implements VoiceDaveService {
  _GatewayFakeDaveSession? session;

  @override
  int get maxProtocolVersion => 1;

  @override
  VoiceDaveEncryptor createEncryptor() => _GatewayFakeDaveEncryptor();

  @override
  VoiceDaveDecryptor createDecryptor() => _GatewayFakeDaveDecryptor();

  @override
  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  }) => session = _GatewayFakeDaveSession(protocolVersion);
}

/// Media cryptors that pass frames through: this file tests the signaling
/// path, and the media plane only needs to exist for the handshake to reach
/// it.
final class _GatewayFakeDaveEncryptor implements VoiceDaveEncryptor {
  @override
  int get protocolVersion => 0;

  @override
  bool get hasKeyRatchet => false;

  @override
  bool get isPassthrough => true;

  @override
  void setKeyRatchet(VoiceDaveKeyRatchet keyRatchet) {}

  @override
  void setPassthrough(bool enabled) {}

  @override
  void assignSsrcToCodec(int ssrc, DaveMediaCodec codec) {}

  @override
  List<int> encrypt({
    required DaveMediaType mediaType,
    required int ssrc,
    required List<int> frame,
  }) => frame;

  @override
  void dispose() {}
}

final class _GatewayFakeDaveDecryptor implements VoiceDaveDecryptor {
  @override
  void transitionToKeyRatchet(VoiceDaveKeyRatchet keyRatchet) {}

  @override
  void transitionToPassthrough(bool enabled) {}

  @override
  List<int> decrypt({
    required DaveMediaType mediaType,
    required List<int> encryptedFrame,
  }) => encryptedFrame;

  @override
  void dispose() {}
}

final class _GatewayFakeDaveSession implements VoiceDaveSession {
  _GatewayFakeDaveSession(this._version);

  int _version;
  List<int>? externalSender;
  List<int>? commit;

  @override
  int get protocolVersion => _version;

  @override
  VoiceDaveKeyRatchet getKeyRatchet(String userId) =>
      throw UnsupportedError('Key ratchets are outside this test');

  @override
  void setProtocolVersion(int version) => _version = version;

  @override
  void setExternalSender(List<int> package) =>
      externalSender = List.of(package);

  @override
  List<int> createKeyPackage() => [9, 8];

  @override
  List<int> processProposals({
    required List<int> proposals,
    required List<String> recognizedUserIds,
  }) => [6];

  @override
  DaveCommitResult processCommit(List<int> commit) {
    this.commit = List.of(commit);
    return const DaveCommitResult(
      status: DaveCommitStatus.applied,
      rosterUserIds: ['bot-1'],
    );
  }

  @override
  DaveCommitResult processWelcome({
    required List<int> welcome,
    required List<String> recognizedUserIds,
  }) => const DaveCommitResult(
    status: DaveCommitStatus.applied,
    rosterUserIds: ['bot-1'],
  );

  @override
  void reset() => _version = 0;

  @override
  void dispose() {}
}
