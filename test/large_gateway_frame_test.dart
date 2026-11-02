import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flucord/src/app_log.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_gateway_framing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

/// The size of a real READY on a small account (`docs/LIVE_CAPTURE.md`).
const _realReadySize = 700 * 1024;

/// A READY of about [size] characters in the real shape: the sanitized fixture,
/// with its guilds repeated.
Map<String, Object?> _readyOfSize(int size, {String session = 'session-a'}) {
  final fixture = File('test/fixtures/gateway/ready_sanitized.json');
  final ready = jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;
  final guilds = ready['guilds']! as List<Object?>;
  final oneRound = [...guilds];
  while (jsonEncode(ready).length < size) {
    guilds.addAll(oneRound);
  }
  return ready..['session_id'] = session;
}

Map<String, Object?> _dispatch(int sequence, String name, Object? data) => {
  'op': 0,
  's': sequence,
  't': name,
  'd': data,
};

/// How many times the event loop turned before [done] finished. A loop held by
/// a decode cannot turn, so this count does not depend on the machine's speed.
Future<int> _loopTurnsUntil(Future<Object?> done) async {
  var turns = 0;
  var finished = false;
  void turn() {
    turns++;
    if (!finished) Timer.run(turn);
  }

  Timer.run(turn);
  await done;
  finished = true;
  return turns;
}

/// The real client on a fake socket, with what it reports in order.
final class _Wire {
  _Wire() {
    addTearDown(gateway.close);
    gateway.events.listen(reported.add);
  }

  final MemoryDesktopWebSocketConnector connector =
      MemoryDesktopWebSocketConnector();
  late final DiscordDesktopGatewayClient gateway = DiscordDesktopGatewayClient(
    authorization: 'test-account',
    properties: const {'os': 'Windows'},
    socketConnector: connector,
  );
  final List<DiscordGatewayEvent> reported = [];

  MemoryDesktopWebSocket get socket => connector.sockets.last;

  static Future<_Wire> connected() async {
    final wire = _Wire();
    await wire.gateway.connect('wss://gateway.discord.gg');
    return wire;
  }

  /// Completes when the client reports the dispatch called [name].
  Future<Object?> dispatched(String name) => gateway.events.firstWhere(
    (event) => event is DiscordGatewayDispatch && event.name == name,
  );

  /// Completes when the client reports [status].
  Future<Object?> reports(DiscordGatewayStatus status) =>
      gateway.events.firstWhere(
        (event) => event is DiscordGatewayStatusEvent && event.status == status,
      );

  /// The dispatches so far, and any reconnect, by name and in order.
  List<String> get story => [
    for (final event in reported)
      switch (event) {
        DiscordGatewayDispatch(:final name) => name,
        DiscordGatewayStatusEvent(status: DiscordGatewayStatus.reconnecting) =>
          'reconnecting',
        _ => '',
      },
  ].where((entry) => entry.isNotEmpty).toList();
}

/// Records what the client logs for the length of a test.
List<String> _recordLog() {
  final lines = <String>[];
  AppLog.redirect = (level, scope, message, error) => lines.add(message);
  addTearDown(() => AppLog.redirect = null);
  return lines;
}

/// How a frame can reach the client, and what the client must then log.
final class _BadFrame {
  const _BadFrame(this.name, this.frame, this.logged);

  final String name;
  final Future<Object?> Function() frame;
  final String logged;
}

const _padding = _realReadySize;
final _broken = '{"op":0,"d":"${'x' * 20}"';
final _brokenAndLarge = '{"op":0,"d":"${'x' * _padding}"';
final _notAnObject = '[${List.filled(5, 1).join(',')}]';
final _notAnObjectAndLarge = '[${List.filled(_padding, 1).join(',')}]';

/// What a socket's worker isolate sends over, across a real isolate boundary.
Future<Object?> _fromSocketWorker(String text) =>
    Isolate.run(() => DiscordGatewayDecodedJsonFrame.read(text));

final _badFrames = [
  _BadFrame('broken and small', () async => _broken, 'failed at frame-json'),
  _BadFrame(
    'broken and large',
    () async => _brokenAndLarge,
    'failed at frame-json',
  ),
  _BadFrame(
    'broken, read by the socket worker',
    () => _fromSocketWorker(_brokenAndLarge),
    'failed at frame-json',
  ),
  _BadFrame('not an object and small', () async => _notAnObject, 'ignored a'),
  _BadFrame(
    'not an object and large',
    () async => _notAnObjectAndLarge,
    'ignored a',
  ),
  _BadFrame(
    'not an object, read by the socket worker',
    () => _fromSocketWorker(_notAnObjectAndLarge),
    'ignored a',
  ),
];

void main() {
  test('a READY of real size leaves the event loop free', () async {
    final wire = await _Wire.connected();
    final frame = jsonEncode(
      _dispatch(1, 'READY', _readyOfSize(_realReadySize)),
    );
    expect(frame.length, greaterThan(_realReadySize));

    final ready = wire.dispatched('READY');
    wire.socket.receiveRaw(frame);
    final turns = await _loopTurnsUntil(ready);

    // A decode on this isolate lets the loop turn once or twice at most.
    expect(turns, greaterThan(20));
  });

  test(
    'frames around a large frame reach the app in the order they came',
    () async {
      final wire = await _Wire.connected();
      final large = _readyOfSize(_realReadySize);

      final last = wire.dispatched('MESSAGE_DELETE');
      wire.socket
        ..receive(_dispatch(1, 'READY', large))
        ..receive(_dispatch(2, 'READY_SUPPLEMENTAL', <String, Object?>{}))
        ..receive(_dispatch(3, 'GUILD_CREATE', large))
        ..receive(_dispatch(4, 'MESSAGE_CREATE', <String, Object?>{}))
        ..receive(_dispatch(5, 'MESSAGE_UPDATE', <String, Object?>{}))
        ..receive(_dispatch(6, 'MESSAGE_DELETE', <String, Object?>{}));
      await last;

      expect(wire.story, [
        'READY',
        'READY_SUPPLEMENTAL',
        'GUILD_CREATE',
        'MESSAGE_CREATE',
        'MESSAGE_UPDATE',
        'MESSAGE_DELETE',
      ]);
    },
  );

  test('a connection that closes behind a large frame ends after it', () async {
    final wire = await _Wire.connected();

    final reconnecting = wire.reports(DiscordGatewayStatus.reconnecting);
    wire.socket.receive(_dispatch(1, 'READY', _readyOfSize(_realReadySize)));
    unawaited(wire.socket.dropConnection());
    await reconnecting;

    expect(wire.story, ['READY', 'reconnecting']);
  });

  test('a connection that fails behind a large frame ends after it', () async {
    final wire = await _Wire.connected();

    final reconnecting = wire.reports(DiscordGatewayStatus.reconnecting);
    wire.socket
      ..receive(_dispatch(1, 'READY', _readyOfSize(_realReadySize)))
      ..failConnection(StateError('The connection failed.'));
    await reconnecting;

    expect(wire.story, ['READY', 'reconnecting']);
  });

  test(
    'a large frame still decoding when its socket is replaced is dropped',
    () async {
      final wire = await _Wire.connected();
      final first = wire.socket;

      first.receive(
        _dispatch(1, 'READY', _readyOfSize(_realReadySize, session: 'old')),
      );
      // One turn: the frame is now with the worker, which needs far longer.
      await Future<void>.delayed(Duration.zero);
      first.sendFailure = StateError('The socket closed mid-frame.');
      wire.gateway.updatePresence(const {'status': 'online'});
      while (wire.connector.sockets.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final ready = wire.dispatched('READY');
      wire.socket.receive(
        _dispatch(1, 'READY', _readyOfSize(_realReadySize, session: 'new')),
      );
      await ready;

      expect(wire.story, ['reconnecting', 'READY']);
      expect(wire.gateway.sessionId, 'new');
    },
  );

  test('frames a socket worker decoded work like any other', () async {
    final wire = await _Wire.connected();

    wire.socket.receiveRaw(
      await _fromSocketWorker(
        jsonEncode({
          'op': 10,
          'd': {'heartbeat_interval': 41250},
        }),
      ),
    );
    final ready = wire.dispatched('MESSAGE_CREATE');
    wire.socket
      ..receiveRaw(
        await _fromSocketWorker(
          jsonEncode(_dispatch(1, 'READY', _readyOfSize(_realReadySize))),
        ),
      )
      ..receiveRaw(
        await _fromSocketWorker(
          jsonEncode(_dispatch(2, 'MESSAGE_CREATE', <String, Object?>{})),
        ),
      );
    await ready;

    expect(wire.socket.frames.first['op'], 2);
    expect(wire.story, ['READY', 'MESSAGE_CREATE']);
  });

  group('a bad frame during sign-in is logged and the socket stays', () {
    for (final bad in _badFrames) {
      test(bad.name, () async {
        final log = _recordLog();
        final wire = _Wire();
        final frame = await bad.frame();

        final workspace = wire.gateway.connectAndReadWorkspace(
          'wss://gateway.discord.gg',
        );
        await Future<void>.delayed(Duration.zero);
        wire.socket
          ..receiveRaw(frame)
          ..receive(_dispatch(1, 'READY', SessionHarness.defaultReady()))
          ..receive(_dispatch(2, 'READY_SUPPLEMENTAL', <String, Object?>{}));
        await workspace;

        expect(log.where((line) => line.contains(bad.logged)), hasLength(1));
        expect(wire.connector.dials, 1);
        expect(wire.socket.isOpen, isTrue);
      });
    }
  });

  testSession(
    'a message right behind a large READY lands after the channel READY brought',
    (tester, session) async {
      const newChannelId = '300000000000000099';
      await session.openChannel(SessionHarness.channelId);
      session.socket.receive(const {'op': 9, 'd': false});
      await session.settle();
      final ready = SessionHarness.defaultReady()
        // Size the app does not read, so the test spends no time on its folds.
        ..['experiments'] = 'x' * _realReadySize;
      final guild = (ready['guilds']! as List<Object?>).single! as Map;
      (guild['channels']! as List<Object?>).add(
        rawChannel(id: newChannelId, name: 'new'),
      );

      await session.dispatch('READY', ready, settle: false);
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: '900000000000000009',
          channelId: newChannelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.friendId,
          content: 'behind the READY',
        ),
        settle: false,
      );
      final newChannel = find.text('new');
      await session.settleUntilDecoded(() => newChannel.evaluate().isNotEmpty);
      await session.settle();

      // Bold is how the row shows that it has an unread message.
      expect(
        tester.widget<Text>(newChannel).style?.fontWeight,
        FontWeight.w600,
      );
    },
  );
}
