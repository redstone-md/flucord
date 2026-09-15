import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../app_log.dart';
import '../../domain/chat_models.dart';
import '../../domain/rich_presence.dart';

import 'discord_rpc_framing.dart';
import 'discord_rpc_transport.dart';
import 'windows_rpc_pipe_transport.dart';

/// How long a connection may sit before its handshake before the server
/// closes it. A game connects and speaks within a few seconds; a connection
/// that does not is a pipe somebody left open.
const Duration rpcHandshakeTimeout = Duration(seconds: 30);

/// Serves the documented local Rich Presence interface over the IPC socket.
///
/// The protocol: a game connects, sends HANDSHAKE (opcode 0) with its client
/// id, and the server answers with the READY dispatch; after that every
/// request is a FRAME. PING is answered with PONG; CLOSE ends the session.
/// Framing is opcode + length + JSON, see discord_rpc_framing.dart. Source:
/// https://github.com/discord/discord-api-docs/blob/main/developers/topics/rpc.mdx
///
/// The server is its own surface: nothing it serves goes through the
/// desktop-user gateway, and its lifetime is the app's.
final class DiscordRpcServer implements RichPresenceService {
  DiscordRpcServer({
    DiscordRpcTransport? transport,
    this.handshakeTimeout = rpcHandshakeTimeout,
  }) : _transportFactory = transport == null
           ? _defaultTransportFactory
           : _constantFactory(transport);

  /// Binds the transport a test built, so the frames can be driven without
  /// a real socket.
  DiscordRpcServer.withTransport(
    DiscordRpcTransport transport, {
    this.handshakeTimeout = rpcHandshakeTimeout,
  }) : _transportFactory = _constantFactory(transport);

  /// How long a connection may sit before its handshake.
  final Duration handshakeTimeout;

  static DiscordRpcTransport Function() _constantFactory(
    DiscordRpcTransport transport,
  ) =>
      () => transport;

  static final DiscordRpcTransport Function() _defaultTransportFactory =
      _defaultTransport;

  static DiscordRpcTransport _defaultTransport() {
    if (Platform.isLinux || Platform.isMacOS) {
      return UnixRpcTransport();
    }
    if (Platform.isWindows) {
      return WindowsNamedPipeRpcTransport();
    }
    return const UnavailableRpcTransport();
  }

  final DiscordRpcTransport Function() _transportFactory;
  final StreamController<List<UserActivity>> _activitiesUpdates =
      StreamController.broadcast();
  final Map<DiscordRpcSocket, _RpcConnection> _connections = {};
  final List<UserActivity> _activities = [];

  /// The name each activity carries. A game that does not name itself in
  /// the command payload is shown under the game's own name.
  String Function(String? clientId) activityNameFor = (clientId) => 'A game';

  DiscordRpcSocketServer? _bound;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  List<UserActivity> get activities => List.unmodifiable(_activities);

  @override
  Stream<List<UserActivity>> get activitiesUpdates => _activitiesUpdates.stream;

  /// The IPC path the server listens on.
  String get socketPath => ipcSocketPath();

  @override
  Future<bool> start() async {
    if (_running) return true;
    try {
      final bound = await _transportFactory().bind();
      _bound = bound;
      _running = true;
      bound.connections.listen(_accept, onDone: _stopAccepting);
      return true;
    } on Object catch (error) {
      AppLog.warning('rpc', 'Rich Presence server did not start', error: error);
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    for (final connection in List.of(_connections.values)) {
      await connection.close();
    }
    _connections.clear();
    await _bound?.close();
    _bound = null;
  }

  void _stopAccepting() {
    _running = false;
    _bound = null;
  }

  void _accept(DiscordRpcSocket socket) {
    if (!_running) {
      socket.close();
      return;
    }
    final connection = _RpcConnection(server: this, socket: socket);
    _connections[socket] = connection;
    connection.closed.then((_) => _forget(connection));
  }

  void _forget(_RpcConnection connection) {
    _connections.remove(connection.socket);
    _republish();
  }

  /// Rebuilds the published list from every connected game's last activity.
  void _republish() {
    final next = <UserActivity>[];
    for (final connection in _connections.values) {
      final activity = connection.activity;
      if (activity != null) next.add(activity);
    }
    final changed =
        next.length != _activities.length ||
        List.generate(
          next.length,
          (index) => next[index] != _activities[index],
        ).any((different) => different);
    _activities
      ..clear()
      ..addAll(next);
    if (changed && !_activitiesUpdates.isClosed) {
      _activitiesUpdates.add(activities);
    }
  }
}

/// One connected game.
final class _RpcConnection {
  _RpcConnection({
    required DiscordRpcServer server,
    required DiscordRpcSocket socket,
  }) : _server = server,
       _socket = socket {
    _handshakeTimer = Timer(server.handshakeTimeout, _closeForIdleHandshake);
    _subscription = socket.incoming.listen(
      _acceptBytes,
      onDone: close,
      onError: (Object error) => close(),
    );
  }

  final DiscordRpcServer _server;
  final DiscordRpcSocket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final DiscordRpcFrameDecoder _decoder = DiscordRpcFrameDecoder();
  late final Timer _handshakeTimer;

  /// The game's id, from the handshake. Everything it publishes rides on it.
  String? _clientId;

  /// Whether the connection has completed the handshake.
  bool _handshaken = false;

  UserActivity? get activity => _activity;
  UserActivity? _activity;

  final Completer<void> _done = Completer<void>();
  bool _closed = false;

  Future<void> get closed => _done.future;

  DiscordRpcSocket get socket => _socket;

  void _closeForIdleHandshake() {
    if (!_handshaken) close();
  }

  void _acceptBytes(Uint8List bytes) {
    final frames = _decoder.push(bytes);
    if (_decoder.isPoisoned) {
      close();
      return;
    }
    for (final frame in frames) {
      _acceptFrame(frame);
    }
  }

  void _acceptFrame(DiscordRpcFrame frame) {
    switch (frame.opcode) {
      case DiscordRpcOpcode.handshake:
        _acceptHandshake(frame.payload);
      case DiscordRpcOpcode.frame:
        if (!_handshaken) {
          _sendErrorReply(frame.payload, code: 4000);
          close();
          return;
        }
        _acceptCommand(frame.payload);
      case DiscordRpcOpcode.ping:
        final nonce = frame.payload['nonce'];
        _send(DiscordRpcOpcode.pong, {'nonce': nonce is String ? nonce : ''});
      case DiscordRpcOpcode.pong:
        break;
      case DiscordRpcOpcode.close:
        close();
    }
  }

  void _acceptHandshake(Map<String, Object?> payload) {
    final clientId = payload['client_id'];
    final version = payload['v'];
    if (clientId is! String || clientId.isEmpty) {
      _sendFrame(DiscordRpcOpcode.close, {'message': 'Invalid client id'});
      close();
      return;
    }
    if (version is! int || version != discordRpcVersion) {
      _sendFrame(DiscordRpcOpcode.close, {'message': 'Invalid version'});
      close();
      return;
    }
    _clientId = clientId;
    _handshaken = true;
    _handshakeTimer.cancel();
    _sendFrame(DiscordRpcOpcode.frame, {
      'cmd': 'DISPATCH',
      'evt': 'READY',
      'data': {
        'v': discordRpcVersion,
        'config': {
          'cdn_host': 'cdn.discordapp.com',
          'api_endpoint': 'discord.com/api',
          'environment': 'production',
        },
        'user': {'id': ''},
      },
    });
  }

  void _acceptCommand(Map<String, Object?> payload) {
    final command = payload['cmd'];
    if (command is! String) {
      _sendErrorReply(payload, code: 4000);
      return;
    }
    switch (command) {
      case 'SET_ACTIVITY':
        _acceptActivity(payload);
      case 'SUBSCRIBE':
      case 'UNSUBSCRIBE':
        _reply(payload, cmd: command, data: {});
      case 'PING':
        _reply(payload, cmd: 'PING', data: {});
      default:
        _sendErrorReply(payload, code: 4002);
    }
  }

  void _acceptActivity(Map<String, Object?> payload) {
    final parsed = RichPresenceActivity.fromPayload(
      payload,
      clientId: _clientId,
    );
    if (parsed == null) {
      _sendErrorReply(payload, code: 4000);
      return;
    }
    final name = _server.activityNameFor(_clientId);
    final activity = richPresenceToActivity(parsed, gameName: name);
    if (activity == null) {
      _sendErrorReply(payload, code: 5000);
      return;
    }
    _activity = activity;
    _server._republish();
    _reply(payload, cmd: 'SET_ACTIVITY', data: _activityData(activity));
  }

  Map<String, Object?> _activityData(UserActivity activity) => {
    'name': activity.name,
    'type': activity.type.wireValue,
    'application_id': ?activity.applicationId,
    'state': ?activity.state,
    'details': ?activity.details,
    'timestamps': ?_timestampsWire(activity.timestamps),
    'assets': ?_assetsWire(activity.assets),
    'party': ?_partyWire(activity.party),
    'secrets': ?_secretsWire(activity.secrets),
    'instance': activity.instance,
  };

  Map<String, Object?>? _timestampsWire(ActivityTimestamps? stamps) {
    if (stamps == null) return null;
    return {'start': ?stamps.startMs, 'end': ?stamps.endMs};
  }

  Map<String, Object?>? _assetsWire(ActivityAssets? assets) {
    if (assets == null) return null;
    return {
      'large_image': ?assets.largeImage,
      'large_text': ?assets.largeText,
      'small_image': ?assets.smallImage,
      'small_text': ?assets.smallText,
    };
  }

  Map<String, Object?>? _partyWire(ActivityParty? party) {
    if (party == null) return null;
    return {
      'id': ?party.id,
      'size': ?(party.hasSize ? [party.currentSize, party.maxSize] : null),
    };
  }

  Map<String, Object?>? _secretsWire(ActivitySecrets? secrets) {
    if (secrets == null) return null;
    return {'join': ?secrets.join, 'match': ?secrets.match};
  }

  void _reply(
    Map<String, Object?> payload, {
    required String cmd,
    Map<String, Object?>? data,
  }) {
    final nonce = payload['nonce'];
    _sendFrame(DiscordRpcOpcode.frame, {
      'cmd': cmd,
      'nonce': nonce is String ? nonce : '',
      'evt': null,
      'data': ?data,
    });
  }

  void _sendErrorReply(Map<String, Object?> payload, {required int code}) {
    final nonce = payload['nonce'];
    _sendFrame(DiscordRpcOpcode.frame, {
      'cmd': 'DISPATCH',
      'nonce': nonce is String ? nonce : '',
      'evt': 'ERROR',
      'data': {'code': code, 'message': ''},
    });
  }

  void _send(DiscordRpcOpcode opcode, Map<String, Object?> payload) =>
      _sendFrame(opcode, payload);

  void _sendFrame(DiscordRpcOpcode opcode, Map<String, Object?> payload) {
    if (_closed) return;
    _socket.send(encodeFrame(opcode, payload));
  }

  Future<void> close() async {
    if (_closed) return _done.future;
    _closed = true;
    _handshakeTimer.cancel();
    await _subscription.cancel();
    await _socket.close();
    if (!_done.isCompleted) _done.complete();
  }
}
