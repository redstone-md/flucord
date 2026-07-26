import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/discord/discord_gateway_framing.dart';
import 'package:flucord/src/data/discord/discord_gateway_transport_codec.dart';

void main() {
  final enabled = Platform.environment['FLUCORD_LIVE_GATEWAY_TEST'] == '1';
  final skip = enabled ? null : 'Set FLUCORD_LIVE_GATEWAY_TEST=1.';
  // The installed profile now negotiates zstd-stream. These two checks are
  // about ETF framing alone, so they dial the same endpoint uncompressed.
  const uncompressed = DiscordDesktopProtocolProfile(clientBuildNumber: 582977);

  test('receives Hello from the live desktop Gateway', () async {
    final socket = await const PlatformDiscordDesktopWebSocketConnector()
        .connect(Uri.parse('wss://gateway.discord.gg/?encoding=json&v=9'));
    addTearDown(socket.close);

    final raw = await socket.messages.first.timeout(
      const Duration(seconds: 20),
    );
    expect(raw, isA<String>());
    final payload = jsonDecode(raw! as String) as Map<String, Object?>;
    expect(payload['op'], 10);
    expect(payload['d'], contains('heartbeat_interval'));
  }, skip: skip);

  test('decodes a live ETF Hello with the desktop framing', () async {
    final uri = uncompressed.connectionUri();
    expect(uri.queryParameters['encoding'], 'etf');
    expect(uri.queryParameters.containsKey('compress'), isFalse);

    final socket = await const PlatformDiscordDesktopWebSocketConnector()
        .connect(uri);
    addTearDown(socket.close);

    final raw = await socket.messages.first.timeout(
      const Duration(seconds: 20),
    );
    expect(raw, isA<Uint8List>());

    final payload = const DiscordGatewayEtfFraming().decode(raw);
    expect(payload, isNotNull);
    expect(payload!['op'], 10);
    expect(payload['d'], isA<Map<String, Object?>>());
    expect(
      (payload['d']! as Map<String, Object?>)['heartbeat_interval'],
      isA<int>(),
    );
  }, skip: skip);

  test('gets a live ACK for an ETF heartbeat Flucord encoded', () async {
    const framing = DiscordGatewayEtfFraming();
    final socket = await const PlatformDiscordDesktopWebSocketConnector()
        .connect(uncompressed.connectionUri());
    addTearDown(socket.close);

    final frames = <Map<String, Object?>>[];
    final subscription = socket.messages.listen((raw) {
      final payload = framing.decode(raw);
      if (payload != null) frames.add(payload);
    });
    addTearDown(subscription.cancel);

    // No credential is involved: Discord acknowledges a heartbeat before
    // Identify, so an opcode 11 reply proves the server unpacked the exact
    // ETF frame Flucord encoded.
    socket.sendBinary(framing.encode(const {'op': 1, 'd': null}) as Uint8List);

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (socket.isOpen &&
        !frames.any((frame) => frame['op'] == 11) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(frames.first['op'], 10);
    expect(frames.map((frame) => frame['op']), contains(11));
  }, skip: skip);

  test('decodes a live zstd-stream Gateway session end to end', () async {
    // The shipped profile connects uncompressed, so this check opts into
    // zstd-stream explicitly. It proves the decoder against the real Gateway
    // but not against a full authenticated READY, which is what has to pass
    // before compression is turned back on by default.
    const profile = DiscordDesktopProtocolProfile(
      clientBuildNumber: 582977,
      negotiatedCompression: 'zstd-stream',
    );
    final uri = profile.connectionUri();
    expect(uri.queryParameters['compress'], 'zstd-stream');

    final codec = DiscordGatewayTransportCodec.forProfile(
      encoding: profile.gatewayEncoding,
      compression: profile.negotiatedCompression,
    );
    final socket = await const PlatformDiscordDesktopWebSocketConnector()
        .connect(uri);
    addTearDown(socket.close);

    final frames = <Map<String, Object?>>[];
    final subscription = socket.messages.listen(
      (raw) => frames.addAll(codec.decode(raw)),
    );
    addTearDown(subscription.cancel);

    // Wait for HELLO, then answer with an ETF heartbeat. Discord acknowledges
    // it before Identify, so an opcode 11 reply proves the whole stack:
    // zstd-stream decompression, ETF decoding, and ETF encoding, all against
    // the production Gateway and without any credential.
    final helloBy = DateTime.now().add(const Duration(seconds: 20));
    while (frames.isEmpty && DateTime.now().isBefore(helloBy)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(frames, isNotEmpty, reason: 'no HELLO arrived');
    expect(frames.first['op'], 10);
    expect(
      (frames.first['d']! as Map<String, Object?>)['heartbeat_interval'],
      isA<int>(),
    );

    socket.sendBinary(codec.encode(const {'op': 1, 'd': null}) as Uint8List);

    final ackBy = DateTime.now().add(const Duration(seconds: 20));
    while (socket.isOpen &&
        !frames.any((frame) => frame['op'] == 11) &&
        DateTime.now().isBefore(ackBy)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(frames.map((frame) => frame['op']), contains(11));
  }, skip: skip);
}
