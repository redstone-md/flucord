library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

part 'discord_winhttp_websocket_bindings.dart';

abstract interface class DiscordDesktopWebSocket {
  /// Emits `String` for text frames and `Uint8List` for binary frames.
  Stream<Object?> get messages;
  bool get isOpen;
  int? get closeCode;

  void send(String data);

  /// Writes one binary frame, as required by the `encoding=etf` Gateway.
  void sendBinary(List<int> data);

  Future<void> close();
}

abstract interface class DiscordDesktopWebSocketConnector {
  Future<DiscordDesktopWebSocket> connect(Uri uri);
}

final class PlatformDiscordDesktopWebSocketConnector
    implements DiscordDesktopWebSocketConnector {
  const PlatformDiscordDesktopWebSocketConnector();

  @override
  Future<DiscordDesktopWebSocket> connect(Uri uri) {
    if (Platform.isWindows) return _WinHttpDiscordDesktopWebSocket.connect(uri);
    return _IoDiscordDesktopWebSocket.connect(uri);
  }
}

final class _IoDiscordDesktopWebSocket implements DiscordDesktopWebSocket {
  _IoDiscordDesktopWebSocket(this._socket);

  final WebSocket _socket;

  static Future<_IoDiscordDesktopWebSocket> connect(Uri uri) async {
    final client = HttpClient()
      ..findProxy = null
      ..userAgent = null;
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: const {
          'Origin': 'https://discord.com',
          'User-Agent': _desktopUserAgent,
        },
        compression: CompressionOptions.compressionOff,
        customClient: client,
      );
      return _IoDiscordDesktopWebSocket(socket);
    } finally {
      client.close();
    }
  }

  @override
  Stream<Object?> get messages => _socket;

  @override
  bool get isOpen => _socket.readyState == WebSocket.open;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  void send(String data) => _socket.add(data);

  @override
  void sendBinary(List<int> data) => _socket.add(Uint8List.fromList(data));

  @override
  Future<void> close() => _socket.close();
}

final class _WinHttpDiscordDesktopWebSocket implements DiscordDesktopWebSocket {
  _WinHttpDiscordDesktopWebSocket._(this._bindings, this._receivePort) {
    _subscription = _receivePort.listen(_acceptWorkerEvent);
  }

  final _WinHttpBindings _bindings;
  final ReceivePort _receivePort;
  final StreamController<Object?> _messages = StreamController();
  final Completer<void> _connected = Completer();
  final Completer<void> _done = Completer();
  late final StreamSubscription<Object?> _subscription;

  int _handle = 0;
  int? _closeCode;
  bool _open = false;
  bool _finishing = false;
  bool _disposed = false;

  /// How long the worker gets to report done after a close frame went out.
  /// The handle's own close timeout bounds the handshake at two seconds, so
  /// anything past this means the server never answered and the forced close
  /// takes over.
  static const _closeGrace = Duration(seconds: 5);

  static Future<_WinHttpDiscordDesktopWebSocket> connect(Uri uri) async {
    if (uri.scheme != 'wss' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'A wss URI is required');
    }
    final receivePort = ReceivePort();
    final socket = _WinHttpDiscordDesktopWebSocket._(
      _WinHttpBindings.open(),
      receivePort,
    );
    try {
      // The isolate is not held on to: it is never killed, and it exits on
      // its own once its bounded native calls return and its handles are
      // closed.
      await Isolate.spawn(_runWinHttpWorker, {
        'uri': uri.toString(),
        'events': receivePort.sendPort,
      });
      await socket._connected.future.timeout(const Duration(seconds: 20));
      return socket;
    } on Object {
      await socket._dispose();
      rethrow;
    }
  }

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  bool get isOpen => _open;

  @override
  int? get closeCode => _closeCode;

  @override
  void send(String data) => _write(utf8.encode(data), _winHttpUtf8Message);

  @override
  void sendBinary(List<int> data) => _write(data, _winHttpBinaryMessage);

  void _write(List<int> bytes, int bufferType) {
    if (!_open) throw StateError('Remote auth socket is closed');
    final buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final error = _bindings.webSocketSend(
        Pointer<Void>.fromAddress(_handle),
        bufferType,
        buffer.cast(),
        bytes.length,
      );
      if (error != 0) {
        throw StateError('WinHTTP WebSocket send failed ($error)');
      }
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    if (_done.isCompleted) return;
    final handle = Pointer<Void>.fromAddress(_handle);
    // Sends our close frame and returns without waiting for the server's, so
    // the main isolate never sits in native code. The worker's blocked
    // receive ends with the server's close frame, and its finally is the only
    // place a handle is closed.
    _bindings.webSocketShutdown(handle, 1000, nullptr, 0);
    if (await _workerDone(_closeGrace)) return;
    // The server never answered. Force the connection closed: the handle's
    // own close timeout bounds this call, and a close cancels a pending
    // receive, which is what ends the worker's loop. The worker is provably
    // still in that receive (done was not reported, and it reports before it
    // closes anything), so this is the one handle use the two isolates share,
    // and it is the documented one. No handle is closed on this side, ever.
    _bindings.webSocketClose(handle, 1000, nullptr, 0);
    if (await _workerDone(_closeGrace)) return;
    await _finish();
  }

  /// Whether the worker reported done inside [timeout].
  Future<bool> _workerDone(Duration timeout) async {
    try {
      await _done.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _acceptWorkerEvent(Object? raw) {
    if (raw is! Map) return;
    switch (raw['type']) {
      case 'connected':
        final handle = raw['handle'];
        if (handle is! int || handle == 0) {
          _failConnection('WinHTTP returned an invalid WebSocket handle.');
          return;
        }
        _handle = handle;
        _open = true;
        if (!_connected.isCompleted) _connected.complete();
        return;
      case 'message':
        final value = raw['value'];
        if ((value is String || value is Uint8List) && !_messages.isClosed) {
          _messages.add(value);
        }
        return;
      case 'error':
        final message = raw['message'];
        final error = StateError(
          message is String ? message : 'WinHTTP remote auth failed.',
        );
        if (!_connected.isCompleted) {
          _connected.completeError(error);
        } else if (_open && !_messages.isClosed) {
          // A socket being closed by us reports its own teardown as an
          // error: the receive cancelled under the close frame. Nobody is
          // listening for failures of a socket they just closed, and the
          // gateway client would only log a reconnect it already started.
          _messages.addError(error);
        }
        return;
      case 'done':
        _open = false;
        _closeCode = raw['closeCode'] as int?;
        if (!_connected.isCompleted) {
          _connected.completeError(
            StateError('WinHTTP remote auth closed before connecting.'),
          );
        }
        unawaited(_finish());
        return;
    }
  }

  void _failConnection(String message) {
    if (!_connected.isCompleted) _connected.completeError(StateError(message));
  }

  Future<void> _finish() async {
    if (_finishing) return _done.future;
    _finishing = true;
    if (!_messages.isClosed) await _messages.close();
    if (!_done.isCompleted) _done.complete();
    await _dispose();
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    _receivePort.close();
    // No kill: the worker may sit inside a native call, which a kill cannot
    // interrupt. Every call it makes is bounded by a handle timeout, so it
    // closes its handles and exits on its own; anything it sends to the
    // closed port is dropped.
  }
}

void _runWinHttpWorker(Map<Object?, Object?> request) {
  final events = request['events'];
  final rawUri = request['uri'];
  if (events is! SendPort || rawUri is! String) return;
  final bindings = _WinHttpBindings.open();
  Pointer<Void> session = nullptr;
  Pointer<Void> connection = nullptr;
  Pointer<Void> upgradeRequest = nullptr;
  Pointer<Void> webSocket = nullptr;
  int? closeCode;
  try {
    final uri = Uri.parse(rawUri);
    using((arena) {
      session = bindings.openSession(
        _desktopUserAgent.toNativeUtf16(allocator: arena),
        _winHttpNoProxy,
        nullptr,
        nullptr,
        0,
      );
      _requireHandle(bindings, session, 'open session');
      connection = bindings.connect(
        session,
        uri.host.toNativeUtf16(allocator: arena),
        uri.hasPort ? uri.port : 443,
        0,
      );
      _requireHandle(bindings, connection, 'connect');
      final target = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      upgradeRequest = bindings.openRequest(
        connection,
        'GET'.toNativeUtf16(allocator: arena),
        target.toNativeUtf16(allocator: arena),
        nullptr,
        nullptr,
        nullptr,
        _winHttpSecure,
      );
      _requireHandle(bindings, upgradeRequest, 'open request');
      _requireSuccess(
        bindings,
        bindings.setOption(
          upgradeRequest,
          _winHttpUpgradeToWebSocket,
          nullptr,
          0,
        ),
        'enable WebSocket upgrade',
      );
      final closeTimeout = arena<Uint32>()..value = _winHttpCloseTimeoutMillis;
      _requireSuccess(
        bindings,
        bindings.setOption(
          upgradeRequest,
          _winHttpWebSocketCloseTimeout,
          closeTimeout.cast(),
          sizeOf<Uint32>(),
        ),
        'set WebSocket close timeout',
      );
      final origin = 'Origin: https://discord.com\r\n'.toNativeUtf16(
        allocator: arena,
      );
      _requireSuccess(
        bindings,
        bindings.addRequestHeaders(
          upgradeRequest,
          origin,
          _winHttpHeaderLengthAuto,
          _winHttpAddHeader | _winHttpReplaceHeader,
        ),
        'set Origin header',
      );
      _requireSuccess(
        bindings,
        bindings.sendRequest(upgradeRequest, nullptr, 0, nullptr, 0, 0, 0),
        'send upgrade request',
      );
      _requireSuccess(
        bindings,
        bindings.receiveResponse(upgradeRequest, nullptr),
        'receive upgrade response',
      );
      final status = arena<Uint32>();
      final statusSize = arena<Uint32>()..value = sizeOf<Uint32>();
      _requireSuccess(
        bindings,
        bindings.queryHeaders(
          upgradeRequest,
          _winHttpStatusCode | _winHttpQueryNumber,
          nullptr,
          status.cast(),
          statusSize,
          nullptr,
        ),
        'read upgrade status',
      );
      if (status.value != 101) {
        throw StateError('WinHTTP WebSocket upgrade returned ${status.value}.');
      }
      webSocket = bindings.completeUpgrade(upgradeRequest, 0);
      _requireHandle(bindings, webSocket, 'complete WebSocket upgrade');
    });
    bindings.closeHandle(upgradeRequest);
    upgradeRequest = nullptr;
    events.send({'type': 'connected', 'handle': webSocket.address});
    closeCode = _receiveWinHttpMessages(bindings, webSocket, events);
  } on Object catch (error) {
    events.send({'type': 'error', 'message': error.toString()});
  } finally {
    // Reported before anything is closed: the main isolate reads `done` as
    // the worker no longer being inside a native call, and only then may it
    // decide the connection is beyond waiting for. Closing a handle the main
    // isolate could still touch is the race this order removes.
    events.send({'type': 'done', 'closeCode': closeCode});
    if (webSocket.address != 0) bindings.closeHandle(webSocket);
    if (upgradeRequest.address != 0) bindings.closeHandle(upgradeRequest);
    if (connection.address != 0) bindings.closeHandle(connection);
    if (session.address != 0) bindings.closeHandle(session);
  }
}

int? _receiveWinHttpMessages(
  _WinHttpBindings bindings,
  Pointer<Void> webSocket,
  SendPort events,
) {
  const bufferSize = 64 * 1024;
  final buffer = calloc<Uint8>(bufferSize);
  final bytesRead = calloc<Uint32>();
  final bufferType = calloc<Uint32>();
  final message = BytesBuilder(copy: false);
  try {
    while (true) {
      final error = bindings.webSocketReceive(
        webSocket,
        buffer.cast(),
        bufferSize,
        bytesRead,
        bufferType,
      );
      if (error != 0) throw StateError('WinHTTP receive failed ($error).');
      if (bufferType.value == _winHttpCloseBuffer) {
        return _queryCloseCode(bindings, webSocket);
      }
      if (bufferType.value > _winHttpUtf8Fragment) {
        throw StateError(
          'WinHTTP received an unknown frame type ${bufferType.value}.',
        );
      }
      message.add(Uint8List.fromList(buffer.asTypedList(bytesRead.value)));
      if (bufferType.value == _winHttpUtf8Message) {
        events.send({
          'type': 'message',
          'value': utf8.decode(message.takeBytes()),
        });
      } else if (bufferType.value == _winHttpBinaryMessage) {
        events.send({'type': 'message', 'value': message.takeBytes()});
      }
    }
  } finally {
    calloc.free(bufferType);
    calloc.free(bytesRead);
    calloc.free(buffer);
  }
}

int? _queryCloseCode(_WinHttpBindings bindings, Pointer<Void> webSocket) {
  final status = calloc<Uint16>();
  final reasonLength = calloc<Uint32>();
  try {
    final error = bindings.webSocketQueryCloseStatus(
      webSocket,
      status,
      nullptr,
      0,
      reasonLength,
    );
    return error == 0 ? status.value : null;
  } finally {
    calloc.free(reasonLength);
    calloc.free(status);
  }
}

void _requireHandle(
  _WinHttpBindings bindings,
  Pointer<Void> handle,
  String operation,
) {
  if (handle.address == 0) {
    throw StateError('WinHTTP $operation failed (${bindings.lastError()}).');
  }
}

void _requireSuccess(_WinHttpBindings bindings, int success, String operation) {
  if (success == 0) {
    throw StateError('WinHTTP $operation failed (${bindings.lastError()}).');
  }
}

const _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9249 '
    'Chrome/138.0.7204.251 Electron/37.6.0 Safari/537.36';
const _winHttpNoProxy = 1;
const _winHttpSecure = 0x00800000;
const _winHttpUpgradeToWebSocket = 114;
const _winHttpWebSocketCloseTimeout = 115;

/// How long the close handshake may take, in milliseconds, on every handle
/// this socket opens. The Windows default is ten seconds. The close path
/// waits [_closeGrace] before forcing the connection closed, so this must
/// stay below that grace: a forced close that outlives its wait would leave
/// the worker cancelled after the main isolate had stopped listening.
const _winHttpCloseTimeoutMillis = 2000;
const _winHttpStatusCode = 19;
const _winHttpQueryNumber = 0x20000000;
const _winHttpAddHeader = 0x20000000;
const _winHttpReplaceHeader = 0x80000000;
const _winHttpHeaderLengthAuto = 0xffffffff;
const _winHttpBinaryMessage = 0;
const _winHttpUtf8Message = 2;
const _winHttpUtf8Fragment = 3;
const _winHttpCloseBuffer = 4;
