import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// One connection a game opened on the transport.
abstract interface class DiscordRpcSocket {
  /// Bytes the connection received, in arrival order.
  Stream<Uint8List> get incoming;

  /// Writes one buffer. The protocol wants a whole frame per write: a reader
  /// that sees the header without the payload drops the connection.
  void send(Uint8List bytes);

  Future<void> close();
}

/// What a transport answers once it is bound: the accepting end of the
/// socket.
abstract interface class DiscordRpcSocketServer {
  /// Every connection a game opens, until [close].
  Stream<DiscordRpcSocket> get connections;

  Future<void> close();
}

/// Opens the transport and hands back its accepting end.
abstract interface class DiscordRpcTransport {
  /// Opens the socket and starts accepting.
  Future<DiscordRpcSocketServer> bind();
}

/// The IPC path Discord documents for its local RPC server.
///
/// On Windows it is a named pipe; on Linux and macOS a unix-domain socket
/// under the runtime directory, falling back through the temp directories to
/// `/tmp`. Paths follow
/// https://github.com/discord/discord-api-docs/blob/main/developers/topics/rpc.mdx.
String ipcSocketPath([int number = 0]) {
  if (Platform.isWindows) {
    return '\\\\.\\pipe\\discord-ipc-$number';
  }
  final base =
      Platform.environment['XDG_RUNTIME_DIR'] ??
      Platform.environment['TMPDIR'] ??
      Platform.environment['TMP'] ??
      Platform.environment['TEMP'] ??
      '/tmp';
  return '$base/discord-ipc-$number';
}

/// Serves over a unix-domain socket (Linux and macOS).
final class UnixRpcTransport implements DiscordRpcTransport {
  UnixRpcTransport({this.path, this.serverSocketFactory});

  /// The path to bind. Defaults to the documented IPC path.
  final String? path;

  /// Opens the server socket. Injected so a test can serve on a socket it
  /// chose.
  final Future<ServerSocket> Function(String path)? serverSocketFactory;

  @override
  Future<DiscordRpcSocketServer> bind() async {
    final address = path ?? ipcSocketPath();
    final factory = serverSocketFactory ?? _listen;
    final socket = await factory(address);
    return _ServerSocketServer(socket);
  }

  static Future<ServerSocket> _listen(String path) => ServerSocket.bind(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
  );
}

final class _ServerSocketServer implements DiscordRpcSocketServer {
  _ServerSocketServer(this._socket);

  final ServerSocket _socket;

  @override
  Stream<DiscordRpcSocket> get connections =>
      _socket.map((socket) => _SocketAdapter(socket));

  @override
  Future<void> close() => _socket.close();
}

final class _SocketAdapter implements DiscordRpcSocket {
  _SocketAdapter(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get incoming => _socket;

  @override
  void send(Uint8List bytes) => _socket.add(bytes);

  @override
  Future<void> close() => _socket.close();
}

/// A transport over a socket server the caller already holds.
///
/// A test drives the server through one of these: the test builds the
/// accepting end itself and speaks the protocol from client sockets of its
/// own.
final class PresetRpcTransport implements DiscordRpcTransport {
  PresetRpcTransport(this._serverFactory);

  final DiscordRpcSocketServer Function() _serverFactory;

  @override
  Future<DiscordRpcSocketServer> bind() async => _serverFactory();
}

/// A connected pair of sockets for a test to speak the protocol through.
///
/// The test's client writes into [client]; the server, accepting over a
/// [PresetRpcTransport] backed by [server], sees those bytes and its replies
/// arrive on [client]'s [DiscordRpcSocket.incoming].
final class RpcSocketPair {
  RpcSocketPair() {
    final clientToServer = StreamController<Uint8List>.broadcast();
    final serverToClient = StreamController<Uint8List>.broadcast();
    client = _PairSocket(
      incoming: serverToClient.stream,
      outgoing: clientToServer,
    );
    server = _PairSocket(
      incoming: clientToServer.stream,
      outgoing: serverToClient,
    );
    accepting = _PairSocketServer(server);
  }

  late final DiscordRpcSocket client;
  late final DiscordRpcSocket server;

  /// The accepting end, for the transport the test hands the server.
  late final DiscordRpcSocketServer accepting;

  /// Reports the server half to the server the first time. A test calls
  /// this once the server has bound the accepting end, the way a real
  /// client's connect would arrive.
  void open() => (accepting as _PairSocketServer).open();

  /// Pushes an error into the server half's incoming stream, the way a
  /// broken connection reports itself.
  void fail() {
    (client as _PairSocket).failWith(const SocketException('broken'));
  }
}

final class _PairSocketServer implements DiscordRpcSocketServer {
  _PairSocketServer(this._server);

  final DiscordRpcSocket _server;
  final StreamController<DiscordRpcSocket> _connections =
      StreamController.broadcast();

  /// Reports the server half to the server as a fresh connection.
  void open() {
    if (!_connections.isClosed) _connections.add(_server);
  }

  @override
  Stream<DiscordRpcSocket> get connections => _connections.stream;

  @override
  Future<void> close() async {
    if (!_connections.isClosed) await _connections.close();
  }
}

final class _PairSocket implements DiscordRpcSocket {
  _PairSocket({
    required Stream<Uint8List> incoming,
    required StreamController<Uint8List> outgoing,
  }) : _incoming = incoming,
       _outgoing = outgoing;

  final Stream<Uint8List> _incoming;
  final StreamController<Uint8List> _outgoing;
  bool _closed = false;

  @override
  Stream<Uint8List> get incoming => _incoming;

  @override
  void send(Uint8List bytes) {
    if (_closed || _outgoing.isClosed) return;
    _outgoing.add(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_outgoing.isClosed) await _outgoing.close();
  }

  /// Pushes an error into this half's incoming stream, for a test driving a
  /// broken connection.
  void failWith(Object error) {
    if (_closed || _outgoing.isClosed) return;
    _outgoing.addError(error);
  }
}

/// A transport on a platform the server does not reach. Binds nothing.
final class UnavailableRpcTransport implements DiscordRpcTransport {
  const UnavailableRpcTransport();

  @override
  Future<DiscordRpcSocketServer> bind() async {
    throw const SocketException('No Rich Presence transport here');
  }
}
