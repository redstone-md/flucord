/// The voice websocket seam, faked: a test reads the frames the client sent
/// and plays the server's side, down to the code it closes with.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_voice_websocket.dart';

/// Hands every dial the same [socket], and counts the dials.
final class FakeVoiceSocketConnector implements DiscordVoiceSocketConnector {
  FakeVoiceSocketConnector(this.socket);

  final FakeVoiceWebSocket socket;
  int connectCount = 0;
  Uri? lastUri;

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async {
    connectCount++;
    lastUri = uri;
    return socket;
  }
}

/// Hands every dial a new socket, the way each connection is its own socket
/// in production. A test plays the server on [dials].
final class FakeVoiceSocketDialer implements DiscordVoiceSocketConnector {
  /// Every socket dialled, oldest first, with the address it was dialled on.
  final List<({Uri uri, FakeVoiceWebSocket socket})> dials = [];

  @override
  Future<DiscordVoiceWebSocket> connect(Uri uri) async {
    final socket = FakeVoiceWebSocket();
    dials.add((uri: uri, socket: socket));
    return socket;
  }
}

final class FakeVoiceWebSocket implements DiscordVoiceWebSocket {
  final StreamController<Object?> _messages = StreamController.broadcast();
  final List<Object> sent = [];
  bool _closed = false;

  /// Whether either side closed the socket.
  bool get isClosed => _closed;

  @override
  int? closeCode;

  @override
  Stream<Object?> get messages => _messages.stream;

  void addJson(Map<String, Object?> payload) =>
      _messages.add(jsonEncode(payload));

  void addBinary(List<int> payload) =>
      _messages.add(Uint8List.fromList(payload));

  /// Closes from the server's side, with the code Discord would send.
  Future<void> closeFromServer(int code) async {
    closeCode = code;
    await _closeMessages();
  }

  /// Set when the socket should behave like one that has closed underneath
  /// the client: `dart:io` throws "StreamSink is closed" on a write.
  bool failSends = false;

  @override
  void send(Object data) {
    if (failSends) throw StateError('StreamSink is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCode ??= code;
    await _closeMessages();
  }

  Future<void> _closeMessages() async {
    if (_closed) return;
    _closed = true;
    await _messages.close();
  }
}
