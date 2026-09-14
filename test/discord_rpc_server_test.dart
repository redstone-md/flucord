import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flucord/src/data/discord_rpc/discord_rpc_framing.dart';
import 'package:flucord/src/data/discord_rpc/discord_rpc_server.dart';
import 'package:flucord/src/data/discord_rpc/discord_rpc_transport.dart';
import 'package:flucord/src/data/discord_rpc/windows_rpc_pipe_transport.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/rich_presence.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server on a transport the test drives, with the client half at hand.
final class _Harness {
  final pair = RpcSocketPair();
  late final DiscordRpcServer server;
  final _TestClient client = _TestClient();

  _Harness({Duration handshakeTimeout = rpcHandshakeTimeout}) {
    server = DiscordRpcServer.withTransport(
      _StaticTransport(pair.accepting),
      handshakeTimeout: handshakeTimeout,
    );
  }

  Future<bool> start() async {
    final started = await server.start();
    if (started) pair.open();
    // The server subscribes to its accepting end after bind; the pump lets
    // that subscription be live before the first handshake is sent.
    await pumpEventQueue();
    return started;
  }

  Future<void> stop() => server.stop();
}

/// A transport that answers the pair's accepting end without binding.
final class _StaticTransport implements DiscordRpcTransport {
  _StaticTransport(this._server);

  final DiscordRpcSocketServer _server;

  @override
  Future<DiscordRpcSocketServer> bind() async => _server;
}

/// The client half of the pair, speaking the protocol.
final class _TestClient {
  final List<DiscordRpcFrame> frames = [];
  final DiscordRpcFrameDecoder _decoder = DiscordRpcFrameDecoder();
  DiscordRpcSocket? _socket;
  StreamSubscription<Uint8List>? _subscription;

  /// Attaches to one client half of a pair.
  void attach(DiscordRpcSocket socket) => _socket = socket;

  void listen() {
    _subscription ??= _socket!.incoming.listen((bytes) {
      for (final frame in _decoder.push(bytes)) {
        frames.add(frame);
      }
    });
  }

  void sendHandshake(String clientId) => _socket!.send(
    encodeFrame(DiscordRpcOpcode.handshake, {
      'v': discordRpcVersion,
      'client_id': clientId,
    }),
  );

  void sendCommand(Map<String, Object?> payload, {String? nonce}) => _socket!
      .send(encodeFrame(DiscordRpcOpcode.frame, {'nonce': ?nonce, ...payload}));

  void sendPing({String nonce = 'n1'}) =>
      _socket!.send(encodeFrame(DiscordRpcOpcode.ping, {'nonce': nonce}));

  void sendRaw(Uint8List bytes) => _socket!.send(bytes);

  void sendClose() => _socket!.send(encodeFrame(DiscordRpcOpcode.close, {}));

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
  }
}

void main() {
  test('a handshake without a client id is closed with a message', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendRaw(encodeFrame(DiscordRpcOpcode.handshake, {'v': 1}));
    await pumpEventQueue();

    expect(harness.client.frames.last.opcode, DiscordRpcOpcode.close);
    expect(harness.server.activities, isEmpty);
    await harness.stop();
  });

  test('a handshake on another protocol version is refused', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendRaw(
      encodeFrame(DiscordRpcOpcode.handshake, {
        'v': 2,
        'client_id': '999999999999999999',
      }),
    );
    await pumpEventQueue();

    expect(harness.client.frames.last.opcode, DiscordRpcOpcode.close);
    await harness.stop();
  });

  test('a command whose cmd is not a string answers an error', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({}, nonce: 'no-cmd');
    await pumpEventQueue();

    final reply = harness.client.frames.last;
    expect(reply.payload['evt'], 'ERROR');
    await harness.stop();
  });

  test('the PING command is echoed back with its nonce', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({'cmd': 'PING'}, nonce: 'ping-cmd');
    await pumpEventQueue();

    final reply = harness.client.frames.last;
    expect(reply.payload['cmd'], 'PING');
    expect(reply.payload['nonce'], 'ping-cmd');
    await harness.stop();
  });

  test('an idle connection closes before its handshake', () async {
    final harness = _Harness(handshakeTimeout: const Duration(milliseconds: 5));
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    // Nothing is handshaken, so the timer closes the connection.
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await pumpEventQueue();
    expect(harness.server.activities, isEmpty);
    await harness.stop();
  });
  test(
    'handshake answers READY and the server reports itself running',
    () async {
      final harness = _Harness();
      harness.client.attach(harness.pair.client);
      harness.client.listen();
      expect(await harness.start(), isTrue);
      expect(harness.server.isRunning, isTrue);

      harness.client.sendHandshake('999999999999999999');
      await pumpEventQueue();

      final ready = harness.client.frames.single;
      expect(ready.opcode, DiscordRpcOpcode.frame);
      expect(ready.payload['evt'], 'READY');
      expect(ready.payload['cmd'], 'DISPATCH');
      final data = ready.payload['data']! as Map<String, Object?>;
      expect(data['v'], 1);
      await harness.stop();
      expect(harness.server.isRunning, isFalse);
    },
  );

  test(
    'SET_ACTIVITY reflects the game activity in the account presence',
    () async {
      final harness = _Harness();
      harness.client.attach(harness.pair.client);
      harness.client.listen();
      await harness.start();

      final updates = <List<UserActivity>>[];
      harness.server.activitiesUpdates.listen(updates.add);

      harness.client.sendHandshake('999999999999999999');
      harness.client.sendCommand({
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': 4242,
          'activity': {'state': 'In a Group', 'details': 'Competitive'},
        },
      }, nonce: 'n-1');
      await pumpEventQueue();

      final activity = harness.server.activities.single;
      expect(activity.name, 'A game');
      expect(activity.type, ActivityType.playing);
      expect(activity.state, 'In a Group');
      expect(activity.details, 'Competitive');
      expect(activity.applicationId, '999999999999999999');
      expect(updates, hasLength(1));

      // The command is echoed back with the activity, as the protocol replies.
      final reply = harness.client.frames.last;
      expect(reply.payload['cmd'], 'SET_ACTIVITY');
      expect(reply.payload['nonce'], 'n-1');
      expect(
        (reply.payload['data']! as Map<String, Object?>)['state'],
        'In a Group',
      );
      await harness.stop();
    },
  );

  test('PING is answered with PONG echoing the nonce', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendPing(nonce: 'keepalive');
    await pumpEventQueue();

    final pong = harness.client.frames.last;
    expect(pong.opcode, DiscordRpcOpcode.pong);
    expect(pong.payload['nonce'], 'keepalive');
    await harness.stop();
  });

  test(
    'a frame before the handshake is refused and the session closed',
    () async {
      final harness = _Harness();
      harness.client.attach(harness.pair.client);
      harness.client.listen();
      await harness.start();

      harness.client.sendCommand({'cmd': 'PING'}, nonce: 'early');
      await pumpEventQueue();

      final reply = harness.client.frames.single;
      expect(reply.payload['evt'], 'ERROR');
      expect(harness.server.activities, isEmpty);
      await harness.stop();
    },
  );

  test(
    'an unparseable stream closes the connection with nothing published',
    () async {
      final harness = _Harness();
      harness.client.attach(harness.pair.client);
      harness.client.listen();
      await harness.start();

      harness.client.sendHandshake('999999999999999999');
      harness.client.sendRaw(Uint8List.fromList([9, 0, 0, 0, 0, 0, 0, 0]));
      await pumpEventQueue();

      expect(harness.server.activities, isEmpty);
      await harness.stop();
    },
  );

  test('CLOSE from the game ends its contribution to the presence', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': 1,
        'activity': {'details': 'At the menu'},
      },
    });
    await pumpEventQueue();
    expect(harness.server.activities, hasLength(1));

    harness.client.sendClose();
    await pumpEventQueue();
    expect(harness.server.activities, isEmpty);
    await harness.stop();
  });

  test('an unknown command answers an error and keeps the session', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({'cmd': 'GET_GUILD'}, nonce: 'unknown');
    await pumpEventQueue();

    final reply = harness.client.frames.last;
    expect(reply.payload['evt'], 'ERROR');
    await harness.stop();
  });

  test('SUBSCRIBE is accepted and echoed', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({
      'cmd': 'SUBSCRIBE',
      'evt': 'ACTIVITY_JOIN',
    }, nonce: 'sub');
    await pumpEventQueue();

    final reply = harness.client.frames.last;
    expect(reply.payload['cmd'], 'SUBSCRIBE');
    expect(reply.payload['nonce'], 'sub');
    await harness.stop();
  });

  test('a rich payload is mapped with the documented limits', () async {
    final payload = {
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': 9999,
        'activity': {
          'state': 'In a Group',
          'details': 'Competitive | In a Match',
          'timestamps': {'start': 1756200000000, 'end': 1756200323000},
          'assets': {
            'large_image': 'numbani_map',
            'large_text': 'Numbani',
            'small_image': 'pharah_profile',
            'small_text': 'Pharah',
          },
          'party': {
            'id': 'party-1',
            'size': [3, 6],
          },
          'secrets': {'join': 'join-secret', 'match': 'match-secret'},
          'instance': true,
        },
      },
      'nonce': '647d814a-4cf8-4fbb-948f-898abd24f55b',
    };

    final parsed = RichPresenceActivity.fromPayload(
      payload,
      clientId: '123456789012345678',
    );
    expect(parsed, isNotNull);
    final activity = richPresenceToActivity(parsed!, gameName: 'Overwatch 2');
    expect(activity, isNotNull);
    expect(activity!.name, 'Overwatch 2');
    expect(activity.state, 'In a Group');
    expect(activity.details, 'Competitive | In a Match');
    expect(activity.timestamps!.startMs, 1756200000000);
    expect(activity.timestamps!.endMs, 1756200323000);
    expect(activity.assets!.largeImage, 'numbani_map');
    expect(activity.party!.currentSize, 3);
    expect(activity.party!.maxSize, 6);
    expect(activity.secrets!.join, 'join-secret');
    expect(activity.instance, isTrue);
    expect(activity.hasFlag(ActivityFlag.instance), isTrue);
    expect(activity.isRichPresence, isTrue);
  });

  test('an activity type the interface refuses arrives as playing', () {
    final activity = richPresenceToActivity(
      RichPresenceActivity(type: 1, state: 'Live'),
      gameName: 'A game',
    );
    expect(activity!.type, ActivityType.playing);
  });

  test('a payload with buttons carries them through the parse', () {
    final parsed = RichPresenceActivity.fromPayload({
      'args': {
        'activity': {
          'details': 'Match live',
          'buttons': ['Ask to Join'],
        },
      },
    });

    expect(parsed!.buttons, ['Ask to Join']);
  });

  test('a payload with nothing to show is refused', () {
    final activity = richPresenceToActivity(
      RichPresenceActivity(type: 0),
      gameName: 'A game',
    );
    expect(activity, isNull);
  });

  test('a listening activity carries its name through', () {
    final activity = richPresenceToActivity(
      RichPresenceActivity(type: 2, details: 'Track title'),
      gameName: 'Spotify',
    );
    expect(activity!.type, ActivityType.listening);
    expect(activity.name, 'Spotify');
    expect(activity.details, 'Track title');
  });

  test('an activity payload the server cannot read answers an error', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({
      'cmd': 'SET_ACTIVITY',
      'args': {'pid': 1},
    });
    await pumpEventQueue();

    final reply = harness.client.frames.last;
    expect(reply.payload['evt'], 'ERROR');
    expect(harness.server.activities, isEmpty);
    await harness.stop();
  });

  test('starting twice is one listener', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    expect(await harness.start(), isTrue);
    expect(await harness.server.start(), isTrue);
    expect(harness.server.isRunning, isTrue);

    // The one connection still answers after a second start.
    harness.client.sendHandshake('999999999999999999');
    await pumpEventQueue();
    expect(harness.client.frames.last.payload['evt'], 'READY');
    await harness.stop();
  });

  test('a connection refused while the server is stopped is closed', () async {
    final harness = _Harness();
    await harness.stop();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    harness.pair.open();
    await pumpEventQueue();

    expect(harness.client.frames, isEmpty);
  });

  test('the wire reply carries the mapped activity back', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': 1,
        'activity': {
          'state': 'In a Group',
          'timestamps': {'start': 1756200000000},
          'assets': {'large_image': 'map', 'large_text': 'Numbani'},
          'party': {
            'id': 'p',
            'size': [2, 4],
          },
          'secrets': {'join': 'secret'},
        },
      },
    });
    await pumpEventQueue();

    final reply = harness.client.frames.last;
    final data = reply.payload['data']! as Map<String, Object?>;
    expect(data['state'], 'In a Group');
    expect(
      (data['timestamps']! as Map<String, Object?>)['start'],
      1756200000000,
    );
    expect((data['assets']! as Map<String, Object?>)['large_image'], 'map');
    expect((data['party']! as Map<String, Object?>)['size'], [2, 4]);
    expect((data['secrets']! as Map<String, Object?>)['join'], 'secret');
    await harness.stop();
  });

  test('the server builds on a platform with no transport', () {
    final server = DiscordRpcServer(transport: const UnavailableRpcTransport());

    expect(server.isRunning, isFalse);
    expect(server.socketPath, ipcSocketPath());
    expect(server.activities, isEmpty);
  });

  test(
    'a start that cannot bind the socket reports itself unavailable',
    () async {
      final server = DiscordRpcServer(
        transport: const UnavailableRpcTransport(),
      );
      addTearDown(server.stop);

      expect(await server.start(), isFalse);
      expect(server.isRunning, isFalse);
    },
  );

  test('stopping a server that never started is quiet', () async {
    final server = DiscordRpcServer(transport: const UnavailableRpcTransport());

    await server.stop();
    expect(server.isRunning, isFalse);
  });

  test('the default constructor binds a transport of its own', () {
    final server = DiscordRpcServer();

    expect(server.socketPath, ipcSocketPath());
  });

  test(
    'an activity that maps to nothing answers the no-eligible error',
    () async {
      final harness = _Harness();
      harness.client.attach(harness.pair.client);
      harness.client.listen();
      await harness.start();

      harness.client.sendHandshake('999999999999999999');
      // A playing activity with no state, no details and no artwork is the
      // one payload the mapper refuses.
      harness.client.sendCommand({
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': 1, 'activity': {}},
      });
      await pumpEventQueue();

      final reply = harness.client.frames.last;
      expect(reply.payload['evt'], 'ERROR');
      expect((reply.payload['data']! as Map<String, Object?>)['code'], 5000);
      await harness.stop();
    },
  );

  test('a socket error closes its connection without publishing', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    // A broken connection reports itself as an error on the stream.
    harness.pair.fail();
    await pumpEventQueue();
    expect(harness.server.activities, isEmpty);
  });

  test(
    'a republish that changes the list emits once with the new order',
    () async {
      final harness = _Harness();
      harness.client.attach(harness.pair.client);
      harness.client.listen();
      await harness.start();

      final updates = <List<UserActivity>>[];
      harness.server.activitiesUpdates.listen(updates.add);

      harness.client.sendHandshake('999999999999999999');
      harness.client.sendCommand({
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': 1,
          'activity': {'details': 'First'},
        },
      });
      await pumpEventQueue();
      expect(updates, hasLength(1));

      harness.client.sendCommand({
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': 1,
          'activity': {'details': 'Second'},
        },
      });
      await pumpEventQueue();
      expect(updates, hasLength(2));
      expect(harness.server.activities.single.details, 'Second');
      await harness.stop();
    },
  );

  test('the payload name wins over the detected name', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': 1,
        'name': 'Elden Ring',
        'activity': {'details': 'Limgrave'},
      },
    });
    await pumpEventQueue();

    final activity = harness.server.activities.single;
    expect(activity.name, 'Elden Ring');
    expect(activity.details, 'Limgrave');
    await harness.stop();
  });

  test('a game that names nothing is shown under the fallback', () async {
    final harness = _Harness();
    harness.client.attach(harness.pair.client);
    harness.client.listen();
    await harness.start();

    harness.client.sendHandshake('999999999999999999');
    harness.client.sendCommand({
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': 1,
        'activity': {'details': 'At the menu'},
      },
    });
    await pumpEventQueue();

    expect(harness.server.activities.single.name, 'A game');
    await harness.stop();
  });

  test('a transport without its native module refuses to bind', () async {
    // The path contract is stated through the withBindings form, which any
    // platform can reach: an absent module is a refusal, not a promise.
    final transport = WindowsNamedPipeRpcTransport.withBindings(
      bindings: null,
      path: ipcSocketPath(0),
    );
    expect(transport.path, ipcSocketPath(0));
    expect(transport.bind(), throwsA(isA<SocketException>()));
  });
}
