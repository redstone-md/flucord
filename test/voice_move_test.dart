import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/application/voice_sound_cues.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_voice_signaling_service.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/data/discord/discord_voice_udp_transport.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';
import 'package:flucord/src/domain/client_sounds.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/voice_connection_bar.dart';
import 'package:flucord/src/presentation/widgets/voice_control.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_gateway.dart';
import 'support/fake_voice_socket.dart';

/// A moderator moves this account to another voice channel of the same
/// server, or out of voice. The real signaling service, voice controller and
/// voice client run over the gateway fake and fake voice sockets; a test plays
/// Discord on both and reads the frames, the room and the sounds.
void main() {
  test('a move on the same endpoint reconnects with the new token', () async {
    final rig = await _MoveRig.inRoom();
    final old = rig.dialer.dials.single.socket;

    rig
      ..seatSelf('voice-2')
      // Discord changes the token on a channel change, even when the
      // endpoint stays the same.
      ..serverUpdate(token: 'token-2', endpoint: 'voice-a.discord.media');
    await _until(() => rig.dialer.dials.length == 2);
    final next = rig.dialer.dials.last;
    await rig.finishHandshake(next.socket);

    expect(next.uri.host, 'voice-a.discord.media');
    expect(_identifyOn(next.socket)['channel_id'], 'voice-2');
    expect(_identifyOn(next.socket)['token'], 'token-2');
    expect(old.isClosed, isTrue);
    expect(rig.voice.connectedChannelId, 'voice-2');
    expect(
      rig.voice.seatedByChannel['voice-2']!.map((seat) => seat.userId),
      contains('me'),
    );
    expect(rig.gateway.voiceStates, isEmpty);
    expect(rig.gateway.voicePings, 0);
  });

  test('a repeated identical voice server update after a move keeps the '
      'connection', () async {
    final rig = await _MoveRig.inRoom();

    rig
      ..seatSelf('voice-2')
      // A duplicate of the update the connection already runs on.
      ..serverUpdate(token: 'token-1', endpoint: 'voice-a.discord.media');
    await _flush();

    expect(rig.voice.connectedChannelId, 'voice-2');
    expect(rig.voice.participants.map((p) => p.userId), contains('friend-2'));
    expect(rig.voice.connectionStatus, VoiceConnectionStatus.ready);
    expect(rig.dialer.dials, hasLength(1));
    expect(rig.dialer.dials.single.socket.isClosed, isFalse);
  });

  test('a move to another voice server reconnects there', () async {
    final rig = await _MoveRig.inRoom();
    final old = rig.dialer.dials.single.socket;

    rig.seatSelf('voice-2');
    await _flush();
    // Discord closes the old socket while the new credentials are on their
    // way. That close is part of the move, not a reason to recover.
    await old.closeFromServer(DiscordVoiceCloseCodes.serverMoved);
    await _flush();
    rig.serverUpdate(token: 'token-2', endpoint: 'voice-b.discord.media');
    await _until(() => rig.dialer.dials.length == 2);
    final next = rig.dialer.dials.last;
    await rig.finishHandshake(next.socket);

    expect(next.uri.host, 'voice-b.discord.media');
    expect(_identifyOn(next.socket)['channel_id'], 'voice-2');
    expect(_identifyOn(next.socket)['token'], 'token-2');
    expect(old.isClosed, isTrue);
    expect(rig.voice.connectedChannelId, 'voice-2');
    expect(rig.voice.connectionStatus, VoiceConnectionStatus.ready);
    expect(rig.gateway.voiceStates, isEmpty);
    expect(rig.gateway.voicePings, 0);
  });

  testWidgets('the voice connection bar names the new channel', (tester) async {
    final rig = (await tester.runAsync(_MoveRig.inRoom))!;
    const names = {'voice-1': 'General', 'voice-2': 'AFK'};
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 236,
            child: VoiceConnectionBar(
              controller: rig.voice,
              channelNameFor: (channelId) => names[channelId],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('General'), findsOneWidget);

    await tester.runAsync(() async {
      rig.seatSelf('voice-2');
      await _flush();
    });
    await tester.pump();

    expect(find.textContaining('AFK'), findsOneWidget);
    expect(find.textContaining('General'), findsNothing);
    await tester.runAsync(rig.close);
  });

  test('mute and deafen carry over, and only the move sound plays', () async {
    final rig = await _MoveRig.inRoom();
    await rig.voice.toggleMute();
    await rig.voice.toggleDeafen();
    rig.seatSelf('voice-1', mute: true, deaf: true);
    await _flush();
    rig.forget();

    // Discord keeps the flags on the move, and the room it lands in.
    rig.seatSelf('voice-2', mute: true, deaf: true);
    rig.serverUpdate(token: 'token-2', endpoint: 'voice-b.discord.media');
    await _until(() => rig.dialer.dials.length == 2);
    await rig.finishHandshake(rig.dialer.dials.last.socket);

    expect(rig.voice.isMuted, isTrue);
    expect(rig.voice.isDeafened, isTrue);
    expect(rig.gateway.voiceStates, isEmpty);
    expect(rig.sounds.played, [ClientSound.userMoved]);
  });

  test('a camera stays in the old room, and the new room is told', () async {
    final rig = await _MoveRig.inRoom();
    expect(await rig.voice.setCameraAnnounced(enabled: true), isTrue);
    rig.forget();

    rig.seatSelf('voice-2');
    rig.serverUpdate(token: 'token-2', endpoint: 'voice-b.discord.media');
    await _until(() => rig.gateway.voiceStates.isNotEmpty);

    expect(rig.voice.isCameraOn, isFalse);
    expect(
      rig.gateway.voiceStates.map(
        (frame) => (frame.channelId, frame.selfVideo),
      ),
      [('voice-2', false)],
    );
  });

  test('a move into a channel with a server mute says so, as a join '
      'does', () async {
    final rig = await _MoveRig.inRoom();

    rig.seatSelf('voice-2', serverMute: true);
    await _flush();

    expect(rig.voice.connectedChannelId, 'voice-2');
    expect(rig.voice.isServerMuted, isTrue);
    expect(VoiceControl.mute(rig.voice).tooltip, contains('Server muted'));
  });

  test('a move into a channel without Speak says why, as a server mute '
      'does', () async {
    final rig = await _MoveRig.inRoom();
    rig.speech.value = {'voice-2': VoiceChannelSpeech.noPermission};

    rig.seatSelf('voice-2');
    await _flush();

    final mute = VoiceControl.mute(rig.voice);
    expect(
      mute.tooltip,
      'You do not have permission to speak in this channel · Mute',
    );
    expect(mute.byServer, isTrue);
    expect(mute.icon, FlucordIcons.micOff);
  });

  test('a move into an AFK channel says the account is suppressed', () async {
    final rig = await _MoveRig.inRoom();

    // Discord suppresses everyone in the AFK channel.
    rig.seatSelf('voice-2', suppress: true);
    await _flush();

    final mute = VoiceControl.mute(rig.voice);
    expect(mute.tooltip, 'You are suppressed in this channel · Mute');
    expect(mute.byServer, isTrue);
  });

  test('a suppressed seat in a Stage is left to the Stage', () async {
    final rig = await _MoveRig.inRoom();
    rig.speech.value = {'voice-2': VoiceChannelSpeech.stage};

    rig.seatSelf('voice-2', suppress: true);
    await _flush();

    expect(VoiceControl.mute(rig.voice).tooltip, 'Mute');
  });

  test('gaining Speak in the room clears the mark at once', () async {
    final rig = await _MoveRig.inRoom();
    rig.speech.value = {'voice-1': VoiceChannelSpeech.noPermission};
    expect(VoiceControl.mute(rig.voice).byServer, isTrue);
    var redraws = 0;
    rig.voice.addListener(() => redraws++);

    rig.speech.value = const {};

    expect(redraws, 1);
    expect(VoiceControl.mute(rig.voice).tooltip, 'Mute');
    expect(VoiceControl.mute(rig.voice).byServer, isFalse);
  });

  test('a move during a reconnect settles in the new channel without the '
      'recovery', () async {
    final rig = await _MoveRig.inRoom(
      reissueFallbackDelay: const Duration(milliseconds: 40),
    );
    // Discord ends the session first: the recovery pings and announces
    // voice-1 again.
    await rig.dialer.dials.single.socket.closeFromServer(
      DiscordVoiceCloseCodes.sessionInvalid,
    );
    await _until(() => rig.gateway.voicePings == 1);
    rig.forget();

    rig
      ..seatSelf('voice-2')
      ..serverUpdate(token: 'token-2', endpoint: 'voice-a.discord.media');
    await _until(() => rig.dialer.dials.length == 2);
    await rig.finishHandshake(rig.dialer.dials.last.socket);
    // Past the recovery's own wait, which would leave and rejoin.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(_identifyOn(rig.dialer.dials.last.socket)['channel_id'], 'voice-2');
    expect(rig.voice.connectedChannelId, 'voice-2');
    expect(rig.voice.connectionStatus, VoiceConnectionStatus.ready);
    expect(rig.gateway.voicePings, 0);
    // One announcement of the new channel, so the recovery's announcement
    // of the old one cannot pull the account back. No leave.
    expect(rig.gateway.voiceStates.map((frame) => frame.channelId), [
      'voice-2',
    ]);
    expect(rig.dialer.dials, hasLength(2));
  });

  test('credentials that arrive just before the move dial the new '
      'channel', () async {
    final rig = await _MoveRig.inRoom();
    // A voice state echo, as a mute toggle gets, leaves the old channel
    // waiting for credentials to pair with.
    rig.seatSelf('voice-1');
    await _flush();

    rig
      ..serverUpdate(token: 'token-2', endpoint: 'voice-b.discord.media')
      ..seatSelf('voice-2');
    await _until(() => rig.dialer.dials.length > 1);
    await rig.finishHandshake(rig.dialer.dials.last.socket);

    expect(_identifyOn(rig.dialer.dials.last.socket)['channel_id'], 'voice-2');
    expect(_identifyOn(rig.dialer.dials.last.socket)['token'], 'token-2');
    expect(rig.voice.connectedChannelId, 'voice-2');
  });

  test('a late echo of a mute is not read as a move', () async {
    final rig = await _MoveRig.inRoom();
    await rig.voice.toggleMute();
    await rig.voice.connect(guildId: 'guild-1', channelId: 'voice-2');

    // Discord answers the mute in voice-1 after the join was sent.
    rig.seatSelf('voice-1', mute: true);
    await _flush();
    expect(rig.voice.connectedChannelId, 'voice-2');

    rig
      ..seatSelf('voice-2', mute: true)
      ..serverUpdate(token: 'token-2', endpoint: 'voice-b.discord.media');
    await _until(() => rig.dialer.dials.length == 2);
    await rig.finishHandshake(rig.dialer.dials.last.socket);

    expect(rig.voice.connectedChannelId, 'voice-2');
    expect(_identifyOn(rig.dialer.dials.last.socket)['channel_id'], 'voice-2');
    expect(rig.sounds.played, isNot(contains(ClientSound.userMoved)));
  });

  test(
    'the echo of the first of two quick joins is not read as a move',
    () async {
      final rig = await _MoveRig.inRoom();
      await rig.voice.connect(guildId: 'guild-1', channelId: 'voice-2');
      await rig.voice.connect(guildId: 'guild-1', channelId: 'voice-3');

      rig.seatSelf('voice-2');
      await _flush();

      expect(rig.voice.connectedChannelId, 'voice-3');
      expect(rig.sounds.played, isNot(contains(ClientSound.userMoved)));
      // A channel the client did not ask for after that is a real move.
      rig.seatSelf('voice-3');
      await _flush();
      rig.seatSelf('voice-2');
      await _flush();
      expect(rig.voice.connectedChannelId, 'voice-2');
    },
  );

  test('a moderator disconnect during a leave-and-rejoin cycle ends the '
      'room', () async {
    final rig = await _MoveRig.inRoom(
      reissueFallbackDelay: const Duration(milliseconds: 20),
    );
    await rig.dialer.dials.single.socket.closeFromServer(
      DiscordVoiceCloseCodes.sessionInvalid,
    );
    // No credentials come back, so the client leaves and rejoins.
    await _until(
      () => rig.gateway.voiceStates.any((frame) => frame.channelId == null),
    );
    rig
      ..forget()
      // Discord answers the cycle's leave and rejoin.
      ..seatSelf(null)
      ..seatSelf('voice-1')
      // Then a moderator disconnects the account.
      ..seatSelf(null);
    await _until(() => rig.voice.connectedChannelId == null);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(rig.voice.connectionStatus, VoiceConnectionStatus.disconnected);
    // What Leave sends, and nothing that would rejoin.
    expect(rig.gateway.voiceStates.map((frame) => frame.channelId), [null]);
    expect(rig.sounds.played, [ClientSound.disconnect]);
  });

  test('a moderator disconnect ends the room like Leave', () async {
    final rig = await _MoveRig.inRoom(
      reissueFallbackDelay: const Duration(milliseconds: 20),
    );
    final socket = rig.dialer.dials.single.socket;

    rig.seatSelf(null);
    await socket.closeFromServer(DiscordVoiceCloseCodes.serverMoved);
    await _until(() => rig.voice.connectedChannelId == null);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(rig.voice.connectionStatus, VoiceConnectionStatus.disconnected);
    expect(rig.voice.participants, isEmpty);
    // What Leave sends, and nothing that would rejoin.
    expect(rig.gateway.voiceStates.map((frame) => frame.channelId), [null]);
    expect(rig.gateway.voicePings, 0);
    expect(rig.dialer.dials, hasLength(1));
    expect(rig.sounds.played, [ClientSound.disconnect]);
  });
}

/// The room the account is in, over the real voice stack.
final class _MoveRig {
  _MoveRig({Duration reissueFallbackDelay = const Duration(seconds: 2)}) {
    service = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _WireSockets(dialer),
      reissueFallbackDelay: reissueFallbackDelay,
    )..setCurrentUserId('me');
    voice = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => service,
      speechIn: (channelId) =>
          speech.value[channelId] ?? VoiceChannelSpeech.open,
      speechChanges: speech,
    );
    cues = VoiceSoundCues.forRoom(
      voice: voice,
      sounds: sounds,
      streams: _streams,
      selfUserId: () => 'me',
      isStage: (_) => false,
      watches: (_) => false,
    );
  }

  final FakeChatGateway gateway = FakeChatGateway();
  final FakeVoiceSocketDialer dialer = FakeVoiceSocketDialer();
  final _RecordingSounds sounds = _RecordingSounds();
  final ChangeNotifier _streams = ChangeNotifier();

  /// Who may speak in each channel, as the workspace would answer. Open
  /// where nothing is set.
  final ValueNotifier<Map<String, VoiceChannelSpeech>> speech = ValueNotifier(
    const {},
  );
  late final DiscordVoiceSignalingService service;
  late final VoiceController voice;
  late final VoiceSoundCues cues;

  /// In voice-1 with its connection up, and a friend seated in voice-2.
  /// Everything the entry recorded is cleared.
  static Future<_MoveRig> inRoom({
    Duration reissueFallbackDelay = const Duration(seconds: 2),
  }) async {
    final rig = _MoveRig(reissueFallbackDelay: reissueFallbackDelay);
    addTearDown(rig.close);
    rig.seat('friend-2', 'voice-2');
    await rig.voice.connect(guildId: 'guild-1', channelId: 'voice-1');
    rig
      ..seatSelf('voice-1')
      ..serverUpdate(token: 'token-1', endpoint: 'voice-a.discord.media');
    await _until(() => rig.dialer.dials.isNotEmpty);
    await rig.finishHandshake(rig.dialer.dials.single.socket);
    expect(rig.voice.connectionStatus, VoiceConnectionStatus.ready);
    rig.forget();
    return rig;
  }

  /// Clears the frames and sounds recorded so far.
  void forget() {
    gateway.voiceStates.clear();
    gateway.voicePings = 0;
    sounds.played.clear();
  }

  /// Discord's self voice state: this account seated in [channelId], or out
  /// of voice when it is null.
  void seatSelf(
    String? channelId, {
    bool mute = false,
    bool deaf = false,
    bool serverMute = false,
    bool suppress = false,
  }) => seat(
    'me',
    channelId,
    mute: mute,
    deaf: deaf,
    serverMute: serverMute,
    suppress: suppress,
  );

  void seat(
    String userId,
    String? channelId, {
    bool mute = false,
    bool deaf = false,
    bool serverMute = false,
    bool suppress = false,
  }) => gateway.dispatch('VOICE_STATE_UPDATE', {
    'guild_id': 'guild-1',
    'channel_id': channelId,
    'user_id': userId,
    'session_id': 'session-$userId',
    'self_mute': mute,
    'self_deaf': deaf,
    'mute': serverMute,
    'suppress': suppress,
  });

  void serverUpdate({required String token, required String endpoint}) =>
      gateway.dispatch('VOICE_SERVER_UPDATE', {
        'guild_id': 'guild-1',
        'token': token,
        'endpoint': endpoint,
      });

  /// Plays Discord's side of a voice socket up to the session description,
  /// once the client has identified on it.
  Future<void> finishHandshake(FakeVoiceWebSocket socket) async {
    await _until(() => _opcodes(socket).isNotEmpty);
    socket.addJson({
      'op': DiscordVoiceGatewayOpcode.ready,
      'd': {
        'ssrc': 42,
        'ip': '127.0.0.1',
        'port': 50000,
        'modes': [_mode],
      },
    });
    await _until(
      () => _opcodes(socket).contains(DiscordVoiceGatewayOpcode.selectProtocol),
    );
    socket.addJson({
      'op': DiscordVoiceGatewayOpcode.sessionDescription,
      'd': {
        'mode': _mode,
        'secret_key': List<int>.generate(32, (index) => index),
        'dave_protocol_version': 0,
      },
    });
    await _until(() => voice.connectionStatus == VoiceConnectionStatus.ready);
  }

  bool _closed = false;

  /// Safe to call twice: a widget test closes on the real event loop first.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cues.dispose();
    voice.dispose();
    await service.close();
  }
}

const _mode = 'aead_aes256_gcm_rtpsize';

/// What the client sent on identify.
Map<String, Object?> _identifyOn(FakeVoiceWebSocket socket) {
  final frame = socket.sent
      .whereType<String>()
      .map((text) => jsonDecode(text) as Map<String, Object?>)
      .firstWhere((frame) => frame['op'] == DiscordVoiceGatewayOpcode.identify);
  return frame['d']! as Map<String, Object?>;
}

Iterable<int?> _opcodes(FakeVoiceWebSocket socket) => socket.sent
    .whereType<String>()
    .map((frame) => (jsonDecode(frame) as Map)['op'] as int?);

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('The wait timed out');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// Call sockets over [_dialer], each with a media path that discovers at
/// once. The stream plane is not part of a move.
final class _WireSockets implements DiscordVoiceSocketFactory {
  _WireSockets(this._dialer);

  final FakeVoiceSocketDialer _dialer;

  @override
  int get maxDaveProtocolVersion => 0;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      DiscordVoiceGatewayClient(
        credentials: credentials,
        maxDaveProtocolVersion: 0,
        socketConnector: _dialer,
        udpTransport: _InstantUdp(),
      );

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) => throw UnsupportedError('Streams are outside this test');
}

final class _InstantUdp implements DiscordVoiceUdpTransport {
  final StreamController<Uint8List> _packets = StreamController.broadcast();

  @override
  Stream<Uint8List> get packets => _packets.stream;

  @override
  Stream<Object> get socketFailures => const Stream.empty();

  @override
  Future<DiscordVoiceIpDiscovery> discover({
    required String host,
    required int port,
    required int ssrc,
  }) async => const DiscordVoiceIpDiscovery(address: '203.0.113.7', port: 1);

  @override
  int send(Uint8List packet) => packet.length;

  @override
  Future<void> close() => _packets.close();
}

final class _RecordingSounds implements ClientSoundPlayer {
  final List<ClientSound> played = [];

  @override
  void play(ClientSound sound) => played.add(sound);

  @override
  void loop(ClientSound sound) {}

  @override
  void stopLoop() {}
}
