part of 'discord_voice_transport_test.dart';

void _handshakeCases() {
  group('Discord voice session signaling', () {
    test('uses the documented main Gateway opcode 4 payload', () {
      final protocol = DiscordGatewayProtocol(token: 'token', intents: 1);
      expect(
        protocol.voiceStateUpdate(
          guildId: 'guild-1',
          channelId: 'voice-1',
          selfMute: true,
          selfDeaf: false,
        ),
        {
          'op': 4,
          'd': {
            'guild_id': 'guild-1',
            'channel_id': 'voice-1',
            'self_mute': true,
            'self_deaf': false,
          },
        },
      );
    });

    test('sends opcode 5 with a literal null payload', () {
      final protocol = DiscordGatewayProtocol(token: 'token', intents: 1);
      expect(protocol.voiceServerPing(), {'op': 5, 'd': null});
    });

    test('assembles credentials in either dispatch order', () {
      for (final stateFirst in [true, false]) {
        final assembler = DiscordVoiceSessionAssembler();
        final events = stateFirst
            ? [_voiceState(), _voiceServer()]
            : [_voiceServer(), _voiceState()];

        final first = assembler.accept(
          eventName: events.first.$1,
          data: events.first.$2,
          currentUserId: 'bot-1',
        );
        final credentials = assembler.accept(
          eventName: events.last.$1,
          data: events.last.$2,
          currentUserId: 'bot-1',
        );

        expect(first, isNull);
        expect(credentials?.guildId, 'guild-1');
        expect(credentials?.channelId, 'voice-1');
        expect(credentials?.sessionId, 'session-1');
        expect(credentials?.endpoint, 'voice.example.test');
      }
    });

    test('ignores voice state updates for other users', () {
      final assembler = DiscordVoiceSessionAssembler();
      assembler.accept(
        eventName: 'VOICE_SERVER_UPDATE',
        data: _voiceServer().$2,
        currentUserId: 'bot-1',
      );

      final credentials = assembler.accept(
        eventName: 'VOICE_STATE_UPDATE',
        data: {..._voiceState().$2, 'user_id': 'someone-else'},
        currentUserId: 'bot-1',
      );

      expect(credentials, isNull);
    });
  });

  group('Discord voice UDP discovery', () {
    test('writes the exact 74-byte big-endian request', () {
      final packet = DiscordVoiceDiscoveryPacket.request(0x01020304);

      expect(packet, hasLength(74));
      expect(packet.sublist(0, 8), [0, 1, 0, 70, 1, 2, 3, 4]);
      expect(packet.sublist(8), everyElement(0));
    });

    test('parses the external address and port response', () {
      final packet = Uint8List(74);
      ByteData.sublistView(packet)
        ..setUint16(0, 2, Endian.big)
        ..setUint16(2, 70, Endian.big)
        ..setUint32(4, 42, Endian.big)
        ..setUint16(72, 50000, Endian.big);
      final address = ascii.encode('203.0.113.7');
      packet.setRange(8, 8 + address.length, address);

      final result = DiscordVoiceDiscoveryPacket.parse(packet);

      expect(result?.address, '203.0.113.7');
      expect(result?.port, 50000);
    });
  });
}
