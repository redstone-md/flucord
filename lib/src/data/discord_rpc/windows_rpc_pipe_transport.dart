import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'discord_rpc_transport.dart';

/// The native surface `flucord_rpc.dll` offers, looked up once.
final class WindowsRpcPipeBindings {
  WindowsRpcPipeBindings(DynamicLibrary library)
    : create = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Pointer<NativeFunction<RpcPipeConnectedNative>>,
              Pointer<NativeFunction<RpcPipeReadNative>>,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            ),
            int Function(
              Pointer<Uint8>,
              Pointer<NativeFunction<RpcPipeConnectedNative>>,
              Pointer<NativeFunction<RpcPipeReadNative>>,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            )
          >('flucord_rpc_create'),
      startRead = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('flucord_rpc_start_read'),
      write = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
            int Function(Pointer<Void>, Pointer<Uint8>, int)
          >('flucord_rpc_write'),
      close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('flucord_rpc_close'),
      exists = library
          .lookupFunction<
            Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('flucord_rpc_exists');

  final int Function(
    Pointer<Uint8> path,
    Pointer<NativeFunction<RpcPipeConnectedNative>> connected,
    Pointer<NativeFunction<RpcPipeReadNative>> read,
    Pointer<Void> userData,
    Pointer<Pointer<Void>> outPipe,
  )
  create;
  final int Function(Pointer<Void> pipe) startRead;
  final int Function(Pointer<Void> pipe, Pointer<Uint8> bytes, int length)
  write;
  final void Function(Pointer<Void> pipe) close;
  final int Function(Pointer<Uint8> path) exists;
}

typedef RpcPipeConnectedNative = Void Function(Pointer<Void> userData);

/// One chunk of bytes a game sent, copied by the receiver before returning.
typedef RpcPipeReadNative =
    Void Function(Pointer<Void> userData, Pointer<Uint8> bytes, Int32 length);

/// Serves Rich Presence over the documented `\\.\pipe\discord-ipc-{n}` named
/// pipe on Windows, through `flucord_rpc.dll`.
///
/// Dart's socket API cannot open a named pipe, so the module owns the HANDLE
/// and this class bridges it onto the [DiscordRpcTransport] interfaces: one
/// accepted game at a time, reads arriving as [DiscordRpcSocket.incoming]
/// chunks, writes handed straight to the module.
final class WindowsNamedPipeRpcTransport implements DiscordRpcTransport {
  WindowsNamedPipeRpcTransport({String? path})
    : this.withBindings(
        bindings: Platform.isWindows ? _openBindings() : null,
        path: path ?? ipcSocketPath(),
      );

  /// The bindings handed in rather than opened, so a test can state that the
  /// module is genuinely absent.
  WindowsNamedPipeRpcTransport.withBindings({
    required WindowsRpcPipeBindings? bindings,
    required this.path,
  }) : _bindings = bindings;

  static WindowsRpcPipeBindings? _openBindings() {
    try {
      return WindowsRpcPipeBindings(DynamicLibrary.open('flucord_rpc.dll'));
    } on Object {
      // A build without the native module still runs; the Rich Presence
      // server reports itself unavailable rather than failing the app.
      return null;
    }
  }

  /// The pipe path to bind. Defaults to the documented IPC path.
  final String path;

  final WindowsRpcPipeBindings? _bindings;

  @override
  Future<DiscordRpcSocketServer> bind() async {
    final bindings = _bindings;
    if (bindings == null) {
      throw const SocketException('No Rich Presence pipe transport here');
    }
    return WindowsRpcPipeServer.open(bindings, path);
  }
}

final class WindowsRpcPipeServer implements DiscordRpcSocketServer {
  WindowsRpcPipeServer._();

  /// Opens the pipe and starts the read pump. The module's reader blocks
  /// until a game connects; the socket is published the moment it does.
  static Future<WindowsRpcPipeServer> open(
    WindowsRpcPipeBindings bindings,
    String path,
  ) async {
    final server = WindowsRpcPipeServer._();
    final nativePath = path.toNativeUtf8();
    final outPipe = calloc<Pointer<Void>>();
    final connected = NativeCallable<RpcPipeConnectedNative>.listener((
      Pointer<Void> userData,
    ) {
      server._onConnected();
    });
    final read = NativeCallable<RpcPipeReadNative>.listener((
      Pointer<Void> userData,
      Pointer<Uint8> bytes,
      int length,
    ) {
      server._onBytes(bytes, length);
    });
    try {
      final status = bindings.create(
        nativePath.cast<Uint8>(),
        connected.nativeFunction,
        read.nativeFunction,
        nullptr,
        outPipe,
      );
      if (status != 0 || outPipe.value == nullptr) {
        throw const SocketException('The Rich Presence pipe could not open');
      }
      server._pipe = outPipe.value;
      server._bindings = bindings;
      server._connected = connected;
      server._read = read;
      server._arm();
      return server;
    } on Object {
      connected.close();
      read.close();
      rethrow;
    } finally {
      calloc.free(nativePath);
      calloc.free(outPipe);
    }
  }

  WindowsRpcPipeBindings? _bindings;
  Pointer<Void> _pipe = nullptr;
  NativeCallable<RpcPipeConnectedNative>? _connected;
  NativeCallable<RpcPipeReadNative>? _read;

  final StreamController<DiscordRpcSocket> _connections =
      StreamController.broadcast();
  _WindowsPipeSocket? _current;
  bool _closed = false;

  @override
  Stream<DiscordRpcSocket> get connections => _connections.stream;

  void _arm() {
    if (_closed) return;
    final socket = _WindowsPipeSocket(this);
    _current = socket;
    _bindings?.startRead(_pipe);
    if (!_connections.isClosed) _connections.add(socket);
  }

  void _onConnected() {
    if (_closed) return;
    final socket = _current;
    if (socket != null) socket.markConnected();
  }

  void _onBytes(Pointer<Uint8> bytes, int length) {
    if (length <= 0) return;
    final socket = _current;
    if (socket == null) return;
    socket.receive(Uint8List.fromList(bytes.asTypedList(length)));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _current?.close();
    _current = null;
    _connected?.close();
    _read?.close();
    if (!_connections.isClosed) await _connections.close();
    _bindings?.close(_pipe);
    _pipe = nullptr;
  }
}

final class _WindowsPipeSocket implements DiscordRpcSocket {
  _WindowsPipeSocket(this._server);

  final WindowsRpcPipeServer _server;
  final StreamController<Uint8List> _incoming = StreamController.broadcast();
  bool _connected = false;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  void markConnected() => _connected = true;

  /// Hands one read chunk to the session. Bytes are copied before the
  /// native buffer is released.
  void receive(Uint8List bytes) {
    if (_incoming.isClosed) return;
    _incoming.add(bytes);
  }

  @override
  void send(Uint8List bytes) {
    if (_server._closed || !_connected) return;
    final bindings = _server._bindings;
    final pipe = _server._pipe;
    if (bindings == null || pipe == nullptr) return;
    final buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      bindings.write(pipe, buffer, bytes.length);
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}
