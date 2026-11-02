import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';

void main() {
  test('the bot client reads as connected after a resume', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final gatewayUrl = 'ws://127.0.0.1:${server.port}';
    var dials = 0;
    final resumed = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      final isFirstDial = ++dials == 1;
      socket.add(
        jsonEncode({
          'op': 10,
          'd': {'heartbeat_interval': 41250},
        }),
      );
      socket.listen((raw) {
        final op = (jsonDecode(raw as String) as Map)['op'];
        if (op == 2 && isFirstDial) {
          socket.add(
            jsonEncode({
              'op': 0,
              's': 1,
              't': 'READY',
              'd': {'session_id': 'session', 'resume_gateway_url': gatewayUrl},
            }),
          );
          // Discord asks the client to dial again, which it does by resuming.
          socket.add(jsonEncode({'op': 7, 'd': null}));
        }
        if (op == 6 && !resumed.isCompleted) {
          socket.add(jsonEncode({'op': 0, 's': 2, 't': 'RESUMED', 'd': {}}));
          resumed.complete();
        }
      });
    });

    final client = DiscordGatewayClient(botToken: 'bot-token');
    addTearDown(client.close);
    final connectedAfterReconnect = Completer<void>();
    var reconnecting = false;
    client.events.listen((event) {
      if (event is! DiscordGatewayStatusEvent) return;
      if (event.status == DiscordGatewayStatus.reconnecting) {
        reconnecting = true;
      }
      if (event.status == DiscordGatewayStatus.connected &&
          reconnecting &&
          !connectedAfterReconnect.isCompleted) {
        connectedAfterReconnect.complete();
      }
    });

    await client.connect(gatewayUrl);
    await resumed.future.timeout(const Duration(seconds: 5));

    await connectedAfterReconnect.future.timeout(const Duration(seconds: 5));
  });
}
